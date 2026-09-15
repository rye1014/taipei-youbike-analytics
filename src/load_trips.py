from __future__ import annotations

import argparse
import os
import re
from pathlib import Path
from typing import Any

import pandas as pd
import pyodbc  # type: ignore[import-not-found]


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
CHUNKSIZE = 200_000

SQL_SERVER_ENV_VAR = "YOUBIKE_SQL_SERVER"
SQL_DATABASE = os.environ.get("YOUBIKE_SQL_DATABASE", "TaipeiYouBikeAnalytics")
SQL_DRIVER = os.environ.get("YOUBIKE_SQL_DRIVER", "ODBC Driver 17 for SQL Server")
STAGING_TABLE = "dbo.stg_trip_import"
FACT_TABLE = "dbo.fact_trips"
LOAD_LOG_TABLE = "dbo.etl_trip_load_log"

SOURCE_FILE_PATTERN = re.compile(r"^\d{6}\.csv$")

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
    sql_server = os.environ.get(SQL_SERVER_ENV_VAR)
    if not sql_server:
        raise RuntimeError(
            f"Set {SQL_SERVER_ENV_VAR} before loading trips into SQL Server."
        )

    return (
        f"DRIVER={{{SQL_DRIVER}}};"
        f"SERVER={sql_server};"
        f"DATABASE={SQL_DATABASE};"
        "Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )


def connect_to_database() -> pyodbc.Connection:
    return pyodbc.connect(build_connection_string(), autocommit=False)


def validate_source_file_name(source_file: str) -> None:
    if not SOURCE_FILE_PATTERN.fullmatch(source_file):
        raise ValueError(
            f"Invalid source file name: {source_file}. Expected YYYYMM.csv."
        )


def discover_source_files() -> list[str]:
    source_files = [
        path.name
        for path in DATA_DIR.glob("*.csv")
        if SOURCE_FILE_PATTERN.fullmatch(path.name)
    ]
    return sorted(source_files)


def get_table_row_count(cursor: pyodbc.Cursor, table_name: str) -> int:
    cursor.execute(f"SELECT COUNT(*) FROM {table_name};")
    row = cursor.fetchone()
    return int(row[0])


def get_source_file_row_count(
    cursor: pyodbc.Cursor,
    table_name: str,
    source_file: str,
) -> int:
    cursor.execute(
        f"SELECT COUNT(*) FROM {table_name} WHERE source_file = ?;",
        source_file,
    )
    row = cursor.fetchone()
    return int(row[0])


def fact_has_source_file(cursor: pyodbc.Cursor, source_file: str) -> bool:
    return get_source_file_row_count(cursor, FACT_TABLE, source_file) > 0


def truncate_staging(cursor: pyodbc.Cursor) -> None:
    cursor.execute(f"TRUNCATE TABLE {STAGING_TABLE};")


def insert_load_log(
    cursor: pyodbc.Cursor,
    *,
    source_file: str,
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
        source_file,
        source_row_count,
        loaded_row_count,
        None,
        status,
        error_message,
    )


def read_trip_chunks(csv_path: Path) -> pd.io.parsers.TextFileReader:
    """Read the fixed headerless monthly CSV in chunks without editing raw data."""
    return pd.read_csv(
        csv_path,
        header=None,
        names=SOURCE_COLUMNS,
        dtype=str,
        keep_default_na=False,
        chunksize=CHUNKSIZE,
        encoding="utf-8",
    )


def build_staging_rows(
    chunk: pd.DataFrame,
    *,
    source_file: str,
    start_row_number: int,
) -> list[tuple[Any, ...]]:
    rows = []
    for row_number, row in enumerate(
        chunk.itertuples(index=False, name=None),
        start=start_row_number,
    ):
        rows.append((source_file, row_number, *row))
    return rows


def load_csv_to_staging(
    connection: pyodbc.Connection,
    *,
    source_file: str,
) -> int:
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
    csv_path = DATA_DIR / source_file
    if not csv_path.exists():
        raise FileNotFoundError(f"Source CSV not found: {csv_path}")

    cursor = connection.cursor()
    cursor.fast_executemany = True

    source_row_count = 0
    loaded_row_count: int | None = None

    try:
        for chunk in read_trip_chunks(csv_path):
            staging_rows = build_staging_rows(
                chunk,
                source_file=source_file,
                start_row_number=source_row_count + 1,
            )
            cursor.executemany(insert_sql, staging_rows)
            source_row_count += len(staging_rows)
            print(f"{source_file}: loaded chunk; cumulative source rows: {source_row_count:,}")

        loaded_row_count = get_source_file_row_count(
            cursor,
            STAGING_TABLE,
            source_file,
        )
        if loaded_row_count != source_row_count:
            raise RuntimeError(
                "Staging row count mismatch: "
                f"source={source_row_count:,}, staging={loaded_row_count:,}"
            )

        insert_load_log(
            cursor,
            source_file=source_file,
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
            source_file=source_file,
            source_row_count=source_row_count,
            loaded_row_count=loaded_row_count,
            status="failed",
            error_message=str(exc)[:1000],
        )
        connection.commit()
        raise


def run_transform_procedure(
    cursor: pyodbc.Cursor,
    *,
    source_file: str,
) -> None:
    cursor.execute(
        "EXEC dbo.usp_transform_trip_file @source_file = ?;",
        source_file,
    )
    while cursor.nextset():
        pass


def process_source_file(
    connection: pyodbc.Connection,
    *,
    source_file: str,
) -> str:
    validate_source_file_name(source_file)

    csv_path = DATA_DIR / source_file
    if not csv_path.exists():
        raise FileNotFoundError(f"Source CSV not found: {csv_path}")

    cursor = connection.cursor()

    if fact_has_source_file(cursor, source_file):
        print(f"{source_file}: skipped; fact table already contains this source_file.")
        return "skipped"

    staging_row_count = get_table_row_count(cursor, STAGING_TABLE)

    if staging_row_count > 0:
        raise RuntimeError(
            f"{STAGING_TABLE} is not empty "
            f"({staging_row_count:,} rows). "
            "Inspect or clear staging before loading another source file."
        )

    staging_row_count = load_csv_to_staging(
        connection,
        source_file=source_file,
    )
    print(f"{source_file}: loaded {staging_row_count:,} rows into staging.")

    cursor = connection.cursor()
    run_transform_procedure(cursor, source_file=source_file)
    connection.commit()

    fact_row_count = get_source_file_row_count(cursor, FACT_TABLE, source_file)
    staging_source_row_count = get_source_file_row_count(
        cursor,
        STAGING_TABLE,
        source_file,
    )
    if fact_row_count != staging_source_row_count:
        raise RuntimeError(
            "Post-transform row count mismatch: "
            f"fact={fact_row_count:,}, staging={staging_source_row_count:,}"
        )

    truncate_staging(cursor)
    connection.commit()
    print(f"{source_file}: transformed {fact_row_count:,} rows into fact_trips.")
    return "loaded"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Load Taipei YouBike trip CSV files into SQL Server."
    )
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument(
        "--file",
        help="Load one source CSV from data/, for example 202503.csv.",
    )
    source_group.add_argument(
        "--all",
        action="store_true",
        help="Load all data/YYYYMM.csv files in ascending file-name order.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.all:
        source_files = discover_source_files()
        if not source_files:
            raise FileNotFoundError(
                f"No source CSV files matching YYYYMM.csv found in {DATA_DIR}."
            )
    else:
        source_files = [args.file]

    with connect_to_database() as connection:
        for source_file in source_files:
            try:
                process_source_file(connection, source_file=source_file)
            except Exception:
                print(f"{source_file}: failed. Stop without processing later files.")
                raise


if __name__ == "__main__":
    main()
