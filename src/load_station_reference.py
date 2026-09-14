from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Any
import pyodbc  # type: ignore[import-not-found]


PROJECT_ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = PROJECT_ROOT / "data" / "raw" / "youbike_immediate.json"
SQL_SERVER = "localhost"
SQL_DATABASE = "TaipeiYouBikeAnalytics"
SQL_DRIVER = "ODBC Driver 17 for SQL Server"
SQL_TABLE = "dbo.station_reference"
STATION_NAME_PREFIX = "YouBike2.0_"

REQUIRED_SOURCE_FIELDS = (
    "sno",
    "sna",
    "sarea",
    "ar",
    "latitude",
    "longitude",
    "Quantity",
    "infoDate",
)


def read_station_snapshot() -> list[dict[str, Any]]:
    """Read the raw YouBike station JSON without modifying the source file."""
    with JSON_PATH.open("r", encoding="utf-8") as source_file:
        data = json.load(source_file)

    if not isinstance(data, list):
        raise ValueError("Expected youbike_immediate.json to contain a list of stations.")

    if not all(isinstance(row, dict) for row in data):
        raise ValueError("Expected every station record to be a JSON object.")

    return data


def remove_youbike_prefix(station_name_raw: str) -> str:
    if station_name_raw.startswith(STATION_NAME_PREFIX):
        return station_name_raw[len(STATION_NAME_PREFIX) :]
    return station_name_raw


def parse_snapshot_date(value: Any) -> date:
    """Convert infoDate from the raw JSON to a Python date."""
    if not isinstance(value, str):
        raise ValueError(f"infoDate must be a YYYY-MM-DD string: {value!r}")
    return date.fromisoformat(value)


def parse_int_or_none(value: Any) -> int | None:
    if value in (None, ""):
        return None
    return int(value)


def parse_float_or_none(value: Any) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def validate_required_fields(row: dict[str, Any], row_number: int) -> None:
    """Stop the load if a raw station row is missing a required field."""
    missing_fields = [field for field in REQUIRED_SOURCE_FIELDS if field not in row]
    if missing_fields:
        raise ValueError(
            f"Row {row_number} is missing required fields: "
            f"{', '.join(missing_fields)}"
        )


def transform_rows(rows: list[dict[str, Any]]) -> list[tuple[Any, ...]]:
    """Select the 9 target columns and apply the required type conversions."""
    transformed_rows = []

    for row_number, row in enumerate(rows, start=1):
        validate_required_fields(row, row_number)

        station_name_raw = str(row["sna"])
        transformed_rows.append(
            (
                str(row["sno"]),
                station_name_raw,
                remove_youbike_prefix(station_name_raw),
                row["sarea"],
                row["ar"],
                parse_float_or_none(row["latitude"]),
                parse_float_or_none(row["longitude"]),
                parse_int_or_none(row["Quantity"]),
                parse_snapshot_date(row["infoDate"]),
            )
        )

    return transformed_rows


def build_connection_string() -> str:
    """Build a SQL Server connection string using Windows Authentication."""
    return (
        f"DRIVER={{{SQL_DRIVER}}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={SQL_DATABASE};"
        "Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )


def load_rows(rows: list[tuple[Any, ...]]) -> None:
    """Insert the transformed station rows into dbo.station_reference."""
    insert_sql = f"""
INSERT INTO {SQL_TABLE} (
    station_id,
    station_name_raw,
    station_name,
    area,
    address,
    latitude,
    longitude,
    capacity,
    snapshot_date
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
"""

    with pyodbc.connect(build_connection_string(), autocommit=False) as connection:
        cursor = connection.cursor()
        cursor.fast_executemany = True
        try:
            cursor.executemany(insert_sql, rows)
            connection.commit()
        except Exception:
            connection.rollback()
            raise


def main() -> None:
    """Read, transform, and load the station reference data."""
    raw_rows = read_station_snapshot()
    transformed_rows = transform_rows(raw_rows)
    load_rows(transformed_rows)
    print(f"Loaded {len(transformed_rows):,} rows into {SQL_DATABASE}.{SQL_TABLE}.")


if __name__ == "__main__":
    main()
