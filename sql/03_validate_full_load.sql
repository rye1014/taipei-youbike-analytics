-- count
SELECT
    source_file,
    COUNT(*) AS row_count
FROM dbo.fact_trips
GROUP BY source_file
ORDER BY source_file;

SELECT COUNT(*) AS total_trips
FROM dbo.fact_trips;

-- date null check 
SELECT
    SUM(CASE WHEN rent_time IS NULL THEN 1 ELSE 0 END) AS rent_time_nulls,
    SUM(CASE WHEN return_time IS NULL THEN 1 ELSE 0 END) AS return_time_nulls,
    SUM(CASE WHEN info_date IS NULL THEN 1 ELSE 0 END) AS info_date_nulls
FROM dbo.fact_trips;

-- duration parsing check 
SELECT
    duration_parse_failed,
    COUNT(*) AS row_count
FROM dbo.fact_trips
GROUP BY duration_parse_failed;

SELECT TOP 50
    source_file,
    row_number_in_file,
    trip_duration_raw
FROM dbo.fact_trips
WHERE duration_parse_failed = 1;

-- bike type
SELECT
    bike_type,
    COUNT(*) AS trip_count
FROM dbo.fact_trips
GROUP BY bike_type
ORDER BY trip_count DESC;

-- station matching (percentage)
SELECT
    CAST(
        100.0 * SUM(CASE WHEN origin_station_id IS NOT NULL THEN 1 ELSE 0 END)
        / COUNT(*)
        AS DECIMAL(5,2)
    ) AS origin_match_pct,

    CAST(
        100.0 * SUM(CASE WHEN destination_station_id IS NOT NULL THEN 1 ELSE 0 END)
        / COUNT(*)
        AS DECIMAL(5,2)
    ) AS destination_match_pct,

    CAST(
        100.0 * SUM(
            CASE
                WHEN origin_station_id IS NOT NULL
                 AND destination_station_id IS NOT NULL
                THEN 1 ELSE 0
            END
        )
        / COUNT(*)
        AS DECIMAL(5,2)
    ) AS both_match_pct
FROM dbo.fact_trips;

-- unmatched stations
SELECT TOP 30
    origin_station_name_raw,
    COUNT(*) AS trip_count
FROM dbo.fact_trips
WHERE origin_station_id IS NULL
GROUP BY origin_station_name_raw
ORDER BY trip_count DESC;

SELECT TOP 30
    destination_station_name_raw,
    COUNT(*) AS trip_count
FROM dbo.fact_trips
WHERE destination_station_id IS NULL
GROUP BY destination_station_name_raw
ORDER BY trip_count DESC;

-- degraded-name flag 
SELECT
    origin_name_degraded,
    COUNT(*) AS row_count
FROM dbo.fact_trips
GROUP BY origin_name_degraded;

SELECT
    destination_name_degraded,
    COUNT(*) AS row_count
FROM dbo.fact_trips
GROUP BY destination_name_degraded;

SELECT TOP 50
    origin_station_name_raw,
    destination_station_name_raw,
    origin_name_degraded,
    destination_name_degraded
FROM dbo.fact_trips
WHERE origin_name_degraded = 1
   OR destination_name_degraded = 1;