# Raw Data

Raw data files are not committed to this repository due to file size.

## Sources

Trip records:

- Taipei YouBike 2.0 rental records
- Source: https://data.gov.tw/dataset/150635

Station reference:

- YouBike 2.0 Taipei real-time station information
- Live JSON endpoint: https://tcgbusfs.blob.core.windows.net/dotapp/youbike/v2/youbike_immediate.json
- Snapshot used in this project: September 11, 2026

## Expected Local Files

This project uses 12 monthly trip CSV files from March 2025 to February 2026 (`202503.csv` through `202602.csv`). The trip loader expects the headerless seven-column format used by these files. 

Place the downloaded monthly trip CSV files directly under:

```text
data/
```

Use monthly filenames in `YYYYMM.csv` format, for example:

```text
data/202503.csv
data/202504.csv
```

Place the station reference JSON at:

```text
data/youbike_immediate.json
```

The station reference used in this project was downloaded on September 11, 2026, and retained locally as `youbike_immediate.json`. The live endpoint is updated regularly and does not provide the same historical snapshot when downloaded later. A newer snapshot may contain different station names, station coverage, or capacity values and may produce different station-matching results. 