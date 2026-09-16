# Taipei YouBike Usage & Station Performance Analytics

## Project Overview

This project analyzes Taipei YouBike 2.0 trip records to understand usage patterns, station activity, directional imbalance, and urban mobility flows.

The project builds a reproducible analytics pipeline using Python, Microsoft SQL Server, and Power BI.

The primary analysis period is March 2025 to February 2026, providing a continuous 12-month window for seasonal and temporal analysis.

## Key Findings

## Dashboard

## Business Questions

The analysis focuses on four areas:

1. **Usage Patterns**
   - How does ridership vary by month, day of week, and hour?
   - How do weekday and weekend usage patterns differ?
   - How does usage differ between regular and e-assist bikes?

2. **Station Performance**
   - Which stations have the highest rental and return activity?
   - Which stations show the strongest directional imbalance?
   - How does station activity vary throughout the day?

3. **Origin-Destination Flows**
   - What are the most common station-to-station routes?
   - How do morning and evening travel flows differ?
   - How do weekday and weekend mobility patterns differ?

4. **Area-Level Mobility**
   - Which areas generate the most YouBike activity?
   - How does activity differ across areas after accounting for station availability?

## Dataset

The raw data files are not included in this GitHub repository. Instructions for obtaining and placing the source files are documented in `data/README.md`.

Data sources:

- Trip records: [臺北市公共自行車2.0租借紀錄](https://data.gov.tw/dataset/150635)
- Station reference: [YouBike2.0臺北市公共自行車即時資訊](https://data.nat.gov.tw/dataset/147580)

Confirmed local audit scope:

- Raw data period: **2020-04 to 2026-02**
- Primary analytical period: **2025-03 to 2026-02**
- Primary analytical period size: **77,389,891** trip records
- Trip data source format: monthly CSV files
- Station reference file: `data/youbike_immediate.json`
- Station reference snapshot date: **2026-09-11**
- Station reference size: **1,800** station records

The station reference is a point-in-time snapshot. It is not a historical station dimension and should not be used to infer past station availability, historical station openings/closures, or historical capacity changes.

## Dataset and Analytical Scope

The full historical dataset from 2020-04 to 2026-02 was evaluated using an automated data audit. Based on that audit, the primary analysis will focus on the recent 12-month period from 2025-03 to 2026-02.

This 12-month period was selected because it provides:

- a complete annual cycle
- consistent bike-type availability
- recent operating data
- more stable schema and encoding
- manageable computational scope for a portfolio project

The broader historical dataset remains useful for understanding schema changes, data quality patterns, and long-term context, but it is not the primary period for final portfolio analysis.

## Data Pipeline

The ingestion pipeline follows the structure:

CSV
-> Python chunked ingestion
-> SQL Server staging table
-> SQL transformation
-> analytical fact table

## Data Model

### `dbo.station_reference`

Reference table containing the current YouBike station snapshot.

### `dbo.stg_trip_import`

Temporary staging table for raw monthly trip records.

### `dbo.fact_trips`

Primary analytical fact table containing cleaned and transformed trip records.

Key fields include:

- source lineage
- rental and return timestamps
- origin and destination station names
- matched station IDs
- trip duration
- bike type
- data-quality flags

## Data Quality & Methodology

### Trip duration

The raw `rent` field represents trip duration in `HH:MM:SS` format.

It is treated as the primary duration source rather than calculating duration from rental and return timestamps, because the timestamp fields appear to be rounded while the duration field retains finer precision.

The raw duration is preserved and separately converted to seconds.

### Station matching

Trip station names are matched to `station_reference.station_name` using exact matching only.

No fuzzy matching or manual remapping is applied.

Trips that cannot be matched are retained, with the corresponding station ID stored as `NULL`.

### Degraded station names

Some source station names contain degraded characters such as:

- `?`
- Unicode replacement character `U+FFFD`

These records are retained and flagged rather than manually corrected.

### Duplicates

Exact duplicate trip rows may exist in the source data.

They are not automatically removed because the dataset does not contain a source transaction ID, and identical rows cannot safely be assumed to represent duplicate journeys.

### Source lineage

No artificial transaction ID is created.

Each trip remains traceable through:

`source_file + row_number_in_file`

## Repository Structure

```
taipei-youbike-analytics/
├── data/
│   ├── 202503.csv
│   ├── ...
│   ├── 202602.csv
│   ├── youbike_immediate.json
│   └── README.md
│
├── sql/
│   ├── 00_create_station_reference.sql
│   ├── 01_create_trip_tables.sql
│   ├── 02_transform_trips.sql
│   └── 03_validate_full_load.sql
│
├── src/
│   ├── load_station_reference.py
│   └── load_trips.py
│
├── README.md
└── .gitignore
```

## Current Status

Completed:

- [x] Dataset audit
- [x] Analytical period selection
- [x] SQL Server data model
- [x] Station reference ingestion
- [x] Chunked trip CSV ingestion
- [x] SQL transformation pipeline
- [x] Full 12-month database load
- [x] Full-load data validation

In progress:

- [ ] Exploratory SQL analysis
- [ ] Python analysis
- [ ] Power BI dashboard
- [ ] Final findings and recommendations
