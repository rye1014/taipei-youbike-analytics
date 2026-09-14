# Taipei YouBike Usage & Station Performance Analytics

## Project Overview

## Dataset

The raw data files are not included in this GitHub repository. Instructions for obtaining and placing the source files are documented in `data/README.md`.

Data sources:

- Trip records: [臺北市公共自行車2.0租借紀錄](https://data.gov.tw/dataset/150635)
- Station reference: [YouBike2.0臺北市公共自行車即時資訊](https://data.nat.gov.tw/dataset/147580)

Confirmed local audit scope:

- Raw data period: 2020-04 to 2026-02
- Primary analytical period: 2025-03 to 2026-02
- Primary analytical period size: approximately 77.4 million trip records
- Trip data source format: monthly CSV files
- Station reference file: `data/youbike_immediate.json`
- Station reference snapshot date: 2026-09-11
- Station reference size: 1,800 station records

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
