USE TaipeiYouBikeAnalytics;
GO

-- 1. Top origin stations by rentals
SELECT TOP 20
    s.station_id,
    s.station_name,
    s.area,
    COUNT(*) AS rental_count
FROM dbo.fact_trips AS f
JOIN dbo.station_reference AS s
    ON f.origin_station_id = s.station_id
GROUP BY
    s.station_id,
    s.station_name,
    s.area
ORDER BY rental_count DESC;

-- 2. Top destination stations by returns
SELECT TOP 20
    s.station_id,
    s.station_name,
    s.area,
    COUNT(*) AS return_count
FROM dbo.fact_trips AS f
JOIN dbo.station_reference AS s
    ON f.destination_station_id = s.station_id
GROUP BY
    s.station_id,
    s.station_name,
    s.area
ORDER BY return_count DESC;

-- Compare the Top 20 rental and return stations and calculate how many stations appear in both rankings
WITH rental_counts AS (
    SELECT
        origin_station_id AS station_id,
        COUNT(*) AS rental_count
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY origin_station_id
),
return_counts AS (
    SELECT
        destination_station_id AS station_id,
        COUNT(*) AS return_count
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY destination_station_id
),
top_rentals AS (
    SELECT TOP (20)
        station_id,
        rental_count
    FROM rental_counts
    ORDER BY rental_count DESC, station_id
),
top_returns AS (
    SELECT TOP (20)
        station_id,
        return_count
    FROM return_counts
    ORDER BY return_count DESC, station_id
)
SELECT
    COUNT(*) AS overlapping_stations
FROM top_rentals AS r
JOIN top_returns AS rt
    ON r.station_id = rt.station_id;


-- 3. Station activity and directions imbalance
-- net_flow is defined as returns - rentals and represents directional trip imbalance
WITH rentals AS (
    SELECT
        origin_station_id AS station_id,
        COUNT(*) AS rental_count
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY origin_station_id
),
returns AS (
    SELECT
        destination_station_id AS station_id,
        COUNT(*) AS return_count
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY destination_station_id
)
SELECT
    s.station_id,
    s.station_name,
    s.area,
    COALESCE(r.rental_count, 0) AS rental_count,
    COALESCE(rt.return_count, 0) AS return_count,
    COALESCE(r.rental_count, 0)
        + COALESCE(rt.return_count, 0) AS total_activity,
    COALESCE(rt.return_count, 0)
        - COALESCE(r.rental_count, 0) AS net_flow
FROM dbo.station_reference AS s
LEFT JOIN rentals AS r
    ON s.station_id = r.station_id
LEFT JOIN returns AS rt
    ON s.station_id = rt.station_id
ORDER BY total_activity DESC;


-- 4. Stations with largest absolute directional imbalance
WITH rentals AS (
    SELECT
        origin_station_id AS station_id,
        COUNT(*) AS rental_count
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY origin_station_id
),
returns AS (
    SELECT
        destination_station_id AS station_id,
        COUNT(*) AS return_count
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY destination_station_id
),
station_activity AS (
    SELECT
        s.station_id,
        s.station_name,
        s.area,
        COALESCE(r.rental_count, 0) AS rental_count,
        COALESCE(rt.return_count, 0) AS return_count    
    FROM dbo.station_reference AS s
    LEFT JOIN rentals AS r
        ON s.station_id = r.station_id
    LEFT JOIN returns AS rt
        ON s.station_id = rt.station_id
)
SELECT TOP 20
    station_id, 
    station_name,
    area,
    rental_count,
    return_count,
    rental_count + return_count AS total_activity,
    return_count - rental_count AS net_flow,
    ABS(return_count - rental_count) As absolute_imbalance
FROM station_activity
WHERE rental_count + return_count > 0
ORDER BY absolute_imbalance DESC;


WITH rentals AS (
    SELECT
        origin_station_id AS station_id,
        COUNT(*) AS rental_count
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY origin_station_id
),
returns AS (
    SELECT
        destination_station_id AS station_id,
        COUNT(*) AS return_count
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY destination_station_id
),
station_activity AS (
    SELECT
        s.station_id,
        s.station_name,
        s.area,
        COALESCE(r.rental_count, 0) AS rental_count,
        COALESCE(rt.return_count, 0) AS return_count    
    FROM dbo.station_reference AS s
    LEFT JOIN rentals AS r
        ON s.station_id = r.station_id
    LEFT JOIN returns AS rt
        ON s.station_id = rt.station_id
)
SELECT TOP 20
    station_id,
    station_name,
    area,
    rental_count,
    return_count,
    rental_count + return_count AS total_activity,
    return_count - rental_count AS net_flow,
    CAST(
        ABS(return_count - rental_count) * 100.0 / NULLIF(rental_count + return_count, 0) AS decimal(5, 2)
    ) AS relative_imbalance_pct
FROM station_activity
WHERE rental_count + return_count >= 100000
ORDER BY relative_imbalance_pct DESC; 