USE TaipeiYouBikeAnalytics;
GO

-- Mon = 1, Sun = 7
SET DATEFIRST 1;
GO

-- 1. Top rental stations
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

-- 2. Top return stations
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

-- 3. Top rental / return overlap
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


-- 4. Station activity and net flow
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


-- 5. Absolute directional imbalance
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

-- 6. Relative directional imbalance
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

-- 7. Hourly rental / return patterns for Top 10 stations
WITH hourly_rentals AS (
    SELECT
        origin_station_id AS station_id,
        DATEPART(hour, rent_time) AS activity_hour,
        COUNT(*) AS rental_count
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY
        origin_station_id,
        DATEPART(hour, rent_time)
),
hourly_returns AS (
    SELECT
        destination_station_id AS station_id,
        DATEPART(hour, return_time) AS activity_hour,
        COUNT(*) AS return_count
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY
        destination_station_id,
        DATEPART(hour, return_time)
),
hourly_activity AS (
    SELECT
        COALESCE(r.station_id, rt.station_id) AS station_id,
        COALESCE(r.activity_hour, rt.activity_hour) AS activity_hour,
        COALESCE(r.rental_count, 0) AS rental_count,
        COALESCE(rt.return_count, 0) AS return_count
    FROM hourly_rentals AS r
    FULL OUTER JOIN hourly_returns AS rt
        ON r.station_id = rt.station_id
       AND r.activity_hour = rt.activity_hour
),
station_totals AS (
    SELECT
        station_id,
        SUM(rental_count + return_count) AS total_activity
    FROM hourly_activity
    GROUP BY station_id
),
top_stations AS (
    SELECT TOP (10)
        station_id,
        total_activity
    FROM station_totals
    ORDER BY
        total_activity DESC,
        station_id
)
SELECT
    s.station_id,
    sr.station_name,
    sr.area,
    h.activity_hour,
    h.rental_count,
    h.return_count,
    h.rental_count + h.return_count AS hourly_activity,
    h.return_count - h.rental_count AS hourly_net_flow
FROM top_stations AS s
JOIN hourly_activity AS h
    ON s.station_id = h.station_id
JOIN dbo.station_reference AS sr
    ON s.station_id = sr.station_id
ORDER BY
    s.total_activity DESC,
    s.station_id,
    h.activity_hour;

-- 8. Morning vs evening peak directional patterns
WITH hourly_rentals AS (
    SELECT
        origin_station_id AS station_id,
        DATEPART(hour, rent_time) AS activity_hour,
        COUNT(*) AS rental_count
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY 
        origin_station_id,
        DATEPART(hour, rent_time)
),
hourly_returns AS (
    SELECT 
        destination_station_id AS station_id,
        DATEPART(hour, return_time) AS activity_hour,
        COUNT(*) AS return_count
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY 
        destination_station_id,
        DATEPART(hour, return_time)
),
hourly_activity AS (
    SELECT
        COALESCE(r.station_id, rt.station_id) AS station_id,
        COALESCE(r.activity_hour, rt.activity_hour) AS activity_hour,
        COALESCE(r.rental_count, 0) AS rental_count,
        COALESCE(rt.return_count, 0) AS return_count
    FROM hourly_rentals r
    FULL OUTER JOIN hourly_returns AS rt
        ON r.station_id = rt.station_id 
        AND r.activity_hour = rt.activity_hour
), 
station_totals AS (
    SELECT 
        station_id,
        SUM(rental_count + return_count) AS total_activity
    FROM hourly_activity
    GROUP BY station_id
), 
top_stations AS (
    SELECT TOP 10
        station_id, 
        total_activity 
    FROM station_totals 
    ORDER BY 
        total_activity DESC, 
        station_id
)
SELECT 
    t.station_id, 
    s.station_name, 
    s.area, 
    SUM(
        CASE 
            WHEN h.activity_hour BETWEEN 7 AND 9 
                THEN h.return_count - h.rental_count
            ELSE 0
        END
    ) AS morning_net_flow, 
    SUM(
        CASE 
            WHEN h.activity_hour BETWEEN 17 AND 19
                THEN h.return_count - h.rental_count
            ELSE 0
        END
    ) AS evening_net_flow
FROM top_stations AS t
JOIN hourly_activity AS h
    ON t.station_id = h.station_id
JOIN dbo.station_reference AS s 
    ON t.station_id = s.station_id 
GROUP BY 
    t.station_id, 
    s.station_name, 
    s.area, 
    t.total_activity 
ORDER BY 
    t.total_activity DESC, 
    t.station_id; 




