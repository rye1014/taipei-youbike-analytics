-- Analysis period: 2025-03-01 to 2026-02-28

USE TaipeiYouBikeAnalytics;
GO

-- Mon = 1, Sun = 7
SET DATEFIRST 1;
GO

-- 1. Monthly ridership
SELECT 
    DATETRUNC(month, rent_time) AS month, 
    COUNT(*) AS trip_count
FROM dbo.fact_trips
GROUP BY DATETRUNC(month, rent_time)
ORDER BY month; 

-- 2. Avg daily ridership by month
-- date coverage check
SELECT
    MIN(CAST(rent_time AS date)) AS first_date,
    MAX(CAST(rent_time AS date)) AS last_date,
    COUNT(DISTINCT CAST(rent_time AS date)) AS active_days
FROM dbo.fact_trips;

-- avg trips per day within each month
WITH daily_trips AS (
    SELECT 
        CAST(rent_time AS date) AS trip_date, 
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    GROUP BY CAST(rent_time AS date)
)
SELECT 
    DATETRUNC(month, trip_date) AS month, 
    AVG(CAST(trip_count AS decimal(18,2))) AS avg_daily_trips
FROM daily_trips
GROUP BY DATETRUNC(month, trip_date)
ORDER BY month; 

-- 3. Avg daily ridership by day of week
WITH daily_trips AS (
    SELECT
        CAST(rent_time AS date) AS trip_date,
        DATEPART(weekday, rent_time) AS weekday_number,
        DATENAME(weekday, rent_time) AS weekday_name,
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    GROUP BY
        CAST(rent_time AS date),
        DATEPART(weekday, rent_time),
        DATENAME(weekday, rent_time)
)
SELECT
    weekday_name,
    AVG(CAST(trip_count AS decimal(18,2))) AS avg_daily_trips
FROM daily_trips
GROUP BY
    weekday_number,
    weekday_name
ORDER BY weekday_number;

-- 4. Hourly ridership
SELECT
    DATEPART(hour, rent_time) AS rent_hour,
    COUNT(*) AS trip_count
FROM dbo.fact_trips
GROUP BY DATEPART(hour, rent_time)
ORDER BY rent_hour;

-- 5. Weekday vs weekend hourly pattern
WITH daily_hourly AS (
    SELECT
        CAST(rent_time AS date) AS trip_date,
        CASE
            WHEN DATEPART(weekday, rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type,
        DATEPART(hour, rent_time) AS rent_hour,
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    GROUP BY
        CAST(rent_time AS date),
        CASE
            WHEN DATEPART(weekday, rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END,
        DATEPART(hour, rent_time)
)
SELECT
    day_type,
    rent_hour,
    AVG(CAST(trip_count AS decimal(18,2))) AS avg_trips
FROM daily_hourly
GROUP BY
    day_type,
    rent_hour
ORDER BY
    rent_hour,
    day_type;

-- 6. Monthly x hourly average pattern
WITH daily_hourly AS (
    SELECT
        CAST(rent_time AS date) AS trip_date,
        DATETRUNC(month, rent_time) AS month,
        DATEPART(hour, rent_time) AS rent_hour,
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    GROUP BY
        CAST(rent_time AS date),
        DATETRUNC(month, rent_time),
        DATEPART(hour, rent_time)
)
SELECT
    month,
    rent_hour,
    AVG(CAST(trip_count AS decimal(18,2))) AS avg_daily_trips
FROM daily_hourly
GROUP BY
    month,
    rent_hour
ORDER BY
    month,
    rent_hour;

-- 7. Trip duration distribution
WITH duration_buckets AS (
    SELECT
        CASE 
            WHEN trip_duration_seconds < 5 * 60 THEN 1
            WHEN trip_duration_seconds < 10 * 60 THEN 2
            WHEN trip_duration_seconds < 20 * 60 THEN 3
            WHEN trip_duration_seconds < 30 * 60 THEN 4
            WHEN trip_duration_seconds < 60 * 60 THEN 5
            ELSE 6
        END AS duration_order,
        CASE 
            WHEN trip_duration_seconds < 5 * 60 THEN '<5 min' -- [0, 5) min
            WHEN trip_duration_seconds < 10 * 60 THEN '5-10 min' -- [5, 10) min
            WHEN trip_duration_seconds < 20 * 60 THEN '10-20 min' -- [10, 20) min
            WHEN trip_duration_seconds < 30 * 60 THEN '20-30 min' -- [20, 30) min
            WHEN trip_duration_seconds < 60 * 60 THEN '30-60 min' -- [30, 60) min
            ELSE '60+ min' -- >= 60 min
        END AS duration_group
    FROM dbo.fact_trips
    WHERE duration_parse_failed = 0
)
SELECT 
    duration_group,
    COUNT(*) AS trip_count,
    CAST(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS decimal(5, 2)
    ) AS percentage_of_parse_success
FROM duration_buckets
GROUP BY
    duration_order, duration_group
ORDER BY duration_order; 

-- 8a. Overall usage by bike type
-- Bike type information is available throughout the full analysis period. 
SELECT
    bike_type,
    COUNT(*) AS trip_count,
    CAST(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
        AS decimal(5,2)
    ) AS trip_share_pct
FROM dbo.fact_trips
WHERE bike_type IS NOT NULL
GROUP BY bike_type
ORDER BY trip_count DESC;

-- 8b. Monthly bike type usage
WITH monthly_bike_type_trips AS (
    SELECT
        DATETRUNC(month, rent_time) AS month,
        bike_type,
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    WHERE bike_type IS NOT NULL
    GROUP BY
        DATETRUNC(month, rent_time),
        bike_type
)
SELECT
    month,
    bike_type,
    trip_count,
    CAST(
        trip_count * 100.0 / SUM(trip_count) OVER (PARTITION BY month) AS decimal(5,2)
    ) AS monthly_percentage
FROM monthly_bike_type_trips
ORDER BY
    month,
    bike_type;

-- 9a. Average hourly trips by bike type
WITH daily_hourly AS (
    SELECT
        CAST(rent_time AS date) AS trip_date,
        bike_type,
        DATEPART(hour, rent_time) AS rent_hour,
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    WHERE bike_type IS NOT NULL
    GROUP BY
        CAST(rent_time AS date),
        bike_type,
        DATEPART(hour, rent_time)
)
SELECT
    bike_type,
    rent_hour,
    AVG(CAST(trip_count AS decimal(18,2))) AS avg_daily_trips
FROM daily_hourly
GROUP BY
    bike_type,
    rent_hour
ORDER BY
    rent_hour,
    bike_type;

-- 9b. Hourly usage distribution by bike type
WITH hourly_trips AS (
    SELECT
        bike_type,
        DATEPART(hour, rent_time) AS rent_hour,
        COUNT(*) AS trip_count
    FROM dbo.fact_trips
    WHERE bike_type IS NOT NULL
    GROUP BY
        bike_type,
        DATEPART(hour, rent_time)
)
SELECT
    bike_type,
    rent_hour,
    trip_count,
    CAST(
        trip_count * 100.0
        / SUM(trip_count) OVER (PARTITION BY bike_type)
        AS decimal(5,2)
    ) AS hourly_share_pct
FROM hourly_trips
ORDER BY
    rent_hour,
    bike_type;
