# Taipei YouBike Usage & Station Performance Analytics

## 1. Project Overview

This project analyzes Taipei YouBike 2.0 trip records to understand usage patterns, station activity, directional imbalance, and origin-destination flows. It covers approximately 77.4 million trip records from March 2025 to February 2026, a continuous 12-month analysis period. 

Python loads the source data into Microsoft SQL Server, where T-SQL handles trip data transformation, validation, and analysis. Power BI presents the results through a three-page interactive dashboard. 

The analysis focuses on four areas: 

- **Usage Patterns:** How does ridership vary across months, days of the week, and hours of the day? What are the trip duration and bike-type usage patterns?
- **Station Performance:** Which stations have the highest activity and the largest absolute or relative rental-return imbalances? How do rental and return flows vary by hour and between morning and evening peaks at the busiest stations?
- **Origin-Destination Flows:** Which routes and station pairs carry the most trips, and how common are same-station returns? How do the top routes differ between morning and evening peaks and between weekdays and weekends?
- **Area-Level Mobility:** How do areas compare in total activity and activity per active station? Which area pairs have the largest trip flows, and how balanced are the two directions?

## 2. Dashboard

The Power BI report presents the analysis across three pages. 

[View the dashboard PDF](powerbi/taipei_youbike_dashboard.pdf)

[Power BI Project](powerbi/taipei_youbike_dashboard.pbip)

### Network Overview

Summarizes overall ridership, monthly average daily trips, weekday and weekend hourly usage patterns, trip duration distribution, and the monthly share of e-assist bike trips. 

![Network Overview](powerbi/images/page-01.jpg)

### Station Performance

Compares station activity, relative directional imbalance, and morning versus evening net flow at the busiest stations. A station selector supports exploring hourly rental and return patterns. 

![Station Performance](powerbi/images/page-02.jpg)

### Mobility Flow

Highlights the most frequent directed station-to-station routes, morning and evening peak routes, inter-area flows, and full-period activity per active station across source-defined areas. 

![Mobility Flow](powerbi/images/page-03.jpg)

The images and PDF provide static views of the report. To explore its interactive features, open the PBIP project in Power BI Desktop with the accompanying `.Report` and `.SemanticModel` directories. 

## 3. Key Findings

### 1. Weekday and weekend usage follow different hourly patterns

Weekday usage shows clear morning and evening peaks, around 08:00 and 17:00-18:00. Weekend usage builds more gradually during the day, without a strong morning peak. 

### 2. Most trips last less than 20 minutes

Approximately **59.1%** of trips with parseable durations lasted less than 10 minutes, and **83.7%** lasted less than 20 minutes.

The distribution shows that YouBike usage is predominantly short in duration, although trip duration alone does not establish travel distance or purpose.

### 3. Station activity and relative imbalance reveal different patterns

**捷運公館站(2號出口)** recorded the highest station activity, with **545,625 rentals** and **592,498 returns**, totaling **1,138,123 activity events**. 

However, among stations with at least 100,000 activity events, **臺大人文館** had the highest relative imbalance at **27.01%**, with 29,009 more rentals than returns. 

These results illustrate that high activity volume and directional imbalance capture different station characteristics. Neither measure shows whether a station ran out of bikes or had no spaces available for returns. 

### 4. Half of the top morning routes appear in reverse in the evening top 20

Among the top 20 directed OD routes during the morning peak (07:00-09:59), **10 routes (50%)** had their reverse routes in the evening top 20 (17:00-19:59). 

This shows that some popular morning routes are also popular in the opposite direction during the evening. The analysis covers both weekdays and weekends and excludes same-station trips. 

The 50% overlap refers specifically to the ranked routes, not all trips or individual riders making return journeys. 

### 5. Area rankings change when activity is compared per active station

**大安區** ranked first in both total activity and average full-period activity per active station, with approximately **147,370 rental/return events per active station**.

In contrast, **中山區** ranked second in total activity but seventh in average activity per active station, with approximately **90,369 events**. 

These comparisons show that total activity and average station-level activity provide different perspectives on area usage. Average activity per active station does not account for station capacity or actual operating days and should not be interpreted as a utilization rate. 

Supporting queries: 

- [Usage patterns](sql/analysis/01_usage_patterns.sql)
- [Station performance](sql/analysis/02_station_performance.sql)
- [OD flows](sql/analysis/03_od_flows.sql)
- [Area analysis](sql/analysis/04_area_analysis.sql)

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

The analytical dataset was designed to preserve source information while making data-quality issues explicit rather than silently correcting or removing records. 

### Trip duration

The raw `rent` field represents trip duration in `HH:MM:SS` format and is treated as the primary duration measure. 

Rental and return timestamps appear to be rounded, while the duration field retains finer time precision. For this reason, trip duration is not recalculated from `rent_time` and `return_time`.

The original duration value is preserved in `trip_duration_raw` and separately converted to `trip_duration_seconds` for analysis. Records that cannot be parsed are retained and flagged using `duration_parse_failed`.

### Station matching

Origin and destination station names are matched to `station_reference.station_name` using exact matching only. 

No fuzzy matching or manual station-name remapping is applied. If a historical station name cannot be matched to the current station reference, the trip is retained and the corresponding station ID remains `NULL`. 

This approach prioritizes reproducibility and avoids introducing uncertain mappings into the analytical dataset.

### Degraded station names

Some source station names contain evidence of character degradation, including:

- ASCII question mark `?`
- Unicode replacement character `U+FFFD`

These values are preserved as they appear in the source and flagged using `origin_name_degraded` or `destination_name_degraded`.

No attempt is made to reconstruct missing characters because the original text cannot be recovered reliably from the affected records.

### Duplicates

Exact duplicate trip rows are not automatically removed.

The source data does not provide a unique transaction identifier, so two identical rows cannot be reliably distinguished as either duplicate records or separate trips with identical attributes.

Removing them would therefore require an unsupported assumption about the source data.

### Source lineage

No artificial trip transaction ID is created.

Each record remains traceable to its source CSV using the combination:

`source_file + row_number_in_file`

This preserves row-level lineage without implying the existence of a source transaction identifier.

### Full-load validation

After all 12 monthly files were loaded and transformed, the final analytical table was validated using `sql/04_validate_full_load.sql`.

| Validation check | Result |
| --- | --- | 
| Analysis period | 2025-03 to 2026-02 | 
| Monthly source files | 12 | 
| Total trip records | 77,389,891 |
| `rent_time` parsing failures | 0 |
| `return_time` parsing failures | 0 |
| `info_date` parsing failures | 0 |
| Duration parsing failures | 2 | 
| Origin station match rate | 99.34% |
| Destination station match rate | 97.81% |
| Both stations matched | 97.21% |
| Degraded origin station names | 158,570 |
| Degraded destination station names | 158,302 |

The validation confirmed that all 12 monthly source files were successfully loaded into `dbo.fact_trips`, producing 77,389,891 trip records for the primary analytical period. 

All rental timestamps, return timestamps, and source dates were parsed successfully. Only two duration values could not be parsed and were retained with `duration_parse_failed = 1`. 

Exact station-name matching linked 99.34% of origin records and 97.81% of destination records to the station reference, while both endpoints were matched for 97.21% of trips. 

A small proportion of station names were flagged as degraded because of source-level character loss. These records, along with unmatched station IDs, were retained rather than manually corrected or excluded. 

The unmatched records are expected in part because the station reference is a point-in-time snapshot dated 2026-09-11 rather than a historical station dimension. 

Detailed validation queries are available in `sql/04_validate_full_load.sql`. 

### Performance optimization 

The final `dbo.fact_trips` table contains more than 77 million records and is primarily used for analytical workloads involving large table scans, aggregations, and grouping operations.

To improve query performance for these workloads, a clustered columnstore index was created on the fact table after the full data load and validation were completed.

A representative monthly ridership aggregation was executed before and after the optimization using the same benchmark query:

| Metric | Before | After | 
| --- | ---: | ---: | 
| Query elapsed time | 9.99 s | 3.73 s | 
| CPU time | 39.47 s | 26.39 s | 
| Table reserved storage | 11.54 GB | 3.57 GB | 

For this benchmark, elapsed query time decreased by approximately 63%, while the table's reserved storage decreased by approximately 69%.

The columnstore optimization is implemented in `sql/05_optimize_fact_table.sql`, and the benchmark query is available in `sql/benchmark/benchmark.sql`.

## Repository Structure

``` text
taipei-youbike-analytics/
├── data/
│   ├── 202503.csv
│   ├── ...
│   ├── 202602.csv
│   ├── youbike_immediate.json
│   └── README.md
│
├── sql/
│   ├── 01_create_station_reference.sql
│   ├── 02_create_trip_tables.sql
│   ├── 03_transform_trips.sql
│   ├── 04_validate_full_load.sql
│   ├── 05_optimize_fact_table.sql
│   ├── benchmark/
│   │   └── benchmark.sql
│   └── analysis
│       ├── 01_usage_patterns.sql
│       ├── 02_station_performance.sql
│       ├── 03_od_flows.sql
│       ├── 04_area_analysis.sql
│       └── 05_powerbi_views.sql
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
- [x] Analytical fact-table optimization

In progress:

- [ ] Exploratory SQL analysis
- [ ] Python analysis
- [ ] Power BI dashboard
- [ ] Final findings and recommendations
