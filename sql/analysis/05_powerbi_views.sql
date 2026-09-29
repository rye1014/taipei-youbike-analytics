-- 1. Daily usage
CREATE OR ALTER VIEW dbo.vw_daily_usage AS 

SELECT 
    CAST(rent_time AS date) AS trip_date, 
    COUNT_BIG(*) AS trip_count
FROM dbo.fact_trips
WHERE rent_time IS NOT NULL
GROUP BY CAST(rent_time AS date); 
GO

-- 2. Network overview
CREATE OR ALTER VIEW dbo.vw_network_kpis AS 

SELECT 
    MIN(trip_date) AS analysis_start_date, 
    MAX(trip_date) AS analysis_end_date, 
    COUNT_BIG(*) AS active_days, 
    SUM(trip_count) AS total_trips, 
    CAST(
        SUM(trip_count) * 1.0 / COUNT_BIG(*) AS decimal(18, 2)
    ) AS avg_daily_trips
FROM dbo.vw_daily_usage; 
GO

-- 3. Monthly usage
CREATE OR ALTER VIEW dbo.vw_monthly_usage AS 

SELECT 
    DATETRUNC(month, trip_date) AS month_start, 
    SUM(trip_count) AS trip_count, 
    COUNT_BIG(*) AS active_days, 
    CAST(
        SUM(trip_count) * 1.0 / COUNT_BIG(*) AS decimal(18, 2)
    ) AS avg_daily_trips
FROM dbo.vw_daily_usage
GROUP BY DATETRUNC(month, trip_date); 
GO

-- 4. Hourly usage by day type 
CREATE OR ALTER VIEW dbo.vw_hourly_usage AS 

WITH day_counts AS (
    SELECT 
        CASE 
            WHEN DATEDIFF(day, '19000101', trip_date) % 7 BETWEEN 0 AND 4
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type, 
        COUNT_BIG(*) AS number_of_days
    FROM dbo.vw_daily_usage
    GROUP BY
        CASE 
            WHEN DATEDIFF(day, '19000101', trip_date) % 7 BETWEEN 0 AND 4
                THEN 'Weekday'
            ELSE 'Weekend'
        END
), 
hourly_counts AS (
    SELECT 
        CASE 
            WHEN DATEDIFF(day, '19000101', CAST(rent_time AS date)) % 7 BETWEEN 0 AND 4
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type, 
        DATEPART(hour, rent_time) AS hour_of_day, 
        COUNT_BIG(*) AS trip_count
    FROM dbo.fact_trips
    WHERE rent_time IS NOT NULL
    GROUP BY 
        CASE 
            WHEN DATEDIFF(day, '19000101', CAST(rent_time AS date)) % 7 BETWEEN 0 AND 4
                THEN 'Weekday'
            ELSE 'Weekend'
        END, 
        DATEPART(hour, rent_time)
)
SELECT 
    h.day_type, 
    h.hour_of_day, 
    h.trip_count, 
    d.number_of_days,
    CAST(
        h.trip_count * 1.0 / d.number_of_days AS decimal(18, 2)
    ) AS avg_hourly_trips
FROM hourly_counts h
JOIN day_counts d
    ON h.day_type = d.day_type; 
GO

-- 5. Trip duration distribution
CREATE OR ALTER VIEW dbo.vw_duration_distribution AS 

WITH duration_buckets AS (
    SELECT 
        CASE 
            WHEN trip_duration_seconds < 300     THEN '<5 min'
            WHEN trip_duration_seconds < 600     THEN '5-10 min'
            WHEN trip_duration_seconds < 1200    THEN '10-20 min'
            WHEN trip_duration_seconds < 1800    THEN '20-30 min'
            WHEN trip_duration_seconds < 3600    THEN '30-60 min'
            ELSE '60+ min'
        END AS duration_bucket, 
        CASE 
            WHEN trip_duration_seconds < 300     THEN 1
            WHEN trip_duration_seconds < 600     THEN 2
            WHEN trip_duration_seconds < 1200    THEN 3
            WHEN trip_duration_seconds < 1800    THEN 4
            WHEN trip_duration_seconds < 3600    THEN 5
            ELSE 6
        END AS bucket_order
    FROM dbo.fact_trips
    WHERE trip_duration_seconds IS NOT NULL
), 
bucket_counts AS (
    SELECT 
        duration_bucket, 
        bucket_order, 
        COUNT_BIG(*) AS trip_count
    FROM duration_buckets 
    GROUP BY 
        duration_bucket, 
        bucket_order
)
SELECT
    duration_bucket, 
    bucket_order, 
    trip_count, 
    CAST(
        trip_count * 100.0 / SUM(trip_count) OVER () AS decimal(5, 2)
    ) AS trip_share_pct
FROM bucket_counts; 
GO

-- 6. Monthly bike type usage
CREATE OR ALTER VIEW dbo.vw_bike_type_monthly AS 

WITH monthly_bike_counts AS (
    SELECT 
        DATETRUNC(month, rent_time) AS month_start, 
        bike_type, 
        COUNT_BIG(*) AS trip_count
    FROM dbo.fact_trips
    WHERE rent_time IS NOT NULL
        AND bike_type IS NOT NULL
    GROUP BY 
        DATETRUNC(month, rent_time), 
        bike_type
)
SELECT 
    month_start, 
    bike_type, 
    trip_count, 
    CAST(
        trip_count * 100.0 / SUM(trip_count) OVER (PARTITION BY month_start) AS decimal(5, 2)
    ) AS monthly_share_pct
FROM monthly_bike_counts; 
GO