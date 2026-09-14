# Raw Data

Raw data files are not committed to this repository due to file size.

## Sources

Trip records:

- Taipei YouBike 2.0 rental records
- Source: https://data.gov.tw/dataset/150635

Station reference:

- YouBike 2.0 Taipei real-time station information
- Source: https://data.nat.gov.tw/dataset/147580

## Expected Local Files

Place the downloaded monthly trip CSV files under:

```text
data/raw/unzipped/
```

Use monthly filenames in `YYYYMM.csv` format, for example:

```text
data/raw/unzipped/202503.csv
data/raw/unzipped/202504.csv
```

Place the station reference JSON at:

```text
data/raw/youbike_immediate.json
```

The station reference is a point-in-time snapshot, not a historical station dimension.
