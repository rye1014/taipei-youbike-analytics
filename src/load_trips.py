from __future__ import annotations

from pathlib import Path
from typing import Any

import pandas as pd
import pyodbc  # type: ignore[import-not-found]


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILE_NAME = "202602.csv"
CSV_PATH = PROJECT_ROOT / "data" / SOURCE_FILE_NAME
CHUNKSIZE = 200_000

SQL_SERVER = "YOUR_SQL_SERVER"
SQL_DATABASE = "TaipeiYouBikeAnalytics"
SQL_DRIVER = "ODBC Driver 17 for SQL Server"
STAGING_TABLE = "dbo.stg_trip_import"
LOAD_LOG_TABLE = "dbo.etl_trip_load_log"

SOURCE_COLUMNS = [
    "rent_time",
    "rent_station",
    "return_time",
    "return_station",
    "rent",
    "type",
    "infodate",
]


def build_connection_string() -> str:
    """Build a SQL Server connection string using Windows Authentication."""
    return (
        f"DRIVER={{{SQL_DRIVER}}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={SQL_DATABASE};"
        "Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )


def get_table_row_count(cursor: pyodbc.Cursor, table_name: str) -> int:
    cursor.execute(f"SELECT COUNT(*) FROM {table_name};")
    row = cursor.fetchone()
    return int(row[0])


def insert_load_log(
    cursor: pyodbc.Cursor,
    *,
    source_row_count: int | None,
    loaded_row_count: int | None,
    status: str,
    error_message: str | None = None,
) -> None:
    insert_sql = f"""
INSERT INTO {LOAD_LOG_TABLE} (
    source_file,
    source_row_count,
    loaded_row_count,
    duration_parse_failures,
    status,
    error_message
)
VALUES (?, ?, ?, ?, ?, ?);
"""
    cursor.execute(
        insert_sql,
        SOURCE_FILE_NAME,
        source_row_count,
        loaded_row_count,
        0,
        status,
        error_message,
    )


def read_trip_chunks() -> pd.io.parsers.TextFileReader:
    """Read the fixed headerless 202602 CSV in chunks without editing raw data."""
    return pd.read_csv(
        CSV_PATH,
        header=None,
        names=SOURCE_COLUMNS,
        dtype=str,
        keep_default_na=False,
        chunksize=CHUNKSIZE,
        encoding="utf-8",
    )


def build_staging_rows(chunk: pd.DataFrame, start_row_number: int) -> list[tuple[Any, ...]]:
    rows = []
    for row_number, row in enumerate(
        chunk.itertuples(index=False, name=None),
        start=start_row_number,
    ):
        rows.append((SOURCE_FILE_NAME, row_number, *row))
    return rows


def load_csv_to_staging() -> int:
    insert_sql = f"""
INSERT INTO {STAGING_TABLE} (
    source_file,
    row_number_in_file,
    rent_time_raw,
    rent_station_name_raw,
    return_time_raw,
    return_station_name_raw,
    trip_duration_raw,
    bike_type_raw,
    info_date_raw
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
"""

    if not CSV_PATH.exists():
        raise FileNotFoundError(f"Source CSV not found: {CSV_PATH}")

    with pyodbc.connect(build_connection_string(), autocommit=False) as connection:
        cursor = connection.cursor()
        cursor.fast_executemany = True

        source_row_count = 0
        loaded_row_count: int | None = None

        try:
            existing_staging_rows = get_table_row_count(cursor, STAGING_TABLE)
            if existing_staging_rows != 0:
                raise RuntimeError(
                    f"{STAGING_TABLE} is not empty "
                    f"({existing_staging_rows:,} rows). Stop without loading."
                )

            for chunk in read_trip_chunks():
                staging_rows = build_staging_rows(
                    chunk,
                    start_row_number=source_row_count + 1,
                )
                cursor.executemany(insert_sql, staging_rows)
                source_row_count += len(staging_rows)
                print(f"Loaded chunk; cumulative source rows: {source_row_count:,}")

            loaded_row_count = get_table_row_count(cursor, STAGING_TABLE)
            if loaded_row_count != source_row_count:
                raise RuntimeError(
                    "Staging row count mismatch: "
                    f"source={source_row_count:,}, staging={loaded_row_count:,}"
                )

            insert_load_log(
                cursor,
                source_row_count=source_row_count,
                loaded_row_count=loaded_row_count,
                status="success",
            )
            connection.commit()
            return source_row_count

        except Exception as exc:
            connection.rollback()
            failure_cursor = connection.cursor()
            insert_load_log(
                failure_cursor,
                source_row_count=source_row_count,
                loaded_row_count=loaded_row_count,
                status="failed",
                error_message=str(exc)[:1000],
            )
            connection.commit()
            raise


def main() -> None:
    loaded_rows = load_csv_to_staging()
    print(
        f"Loaded {loaded_rows:,} rows from {SOURCE_FILE_NAME} "
        f"into {SQL_DATABASE}.{STAGING_TABLE}."
    )


if __name__ == "__main__":
    main()
