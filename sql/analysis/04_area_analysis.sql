-- Area-level analyses includes only trips where both origin and destination stations are successfully matched to station_reference. 
-- This differs from 02_station_performance.sql, where rental and return activity are counted independently by matched endpoint. 

USE TaipeiYouBikeAnalytics;
GO

-- Mon = 1, Sun = 7
SET DATEFIRST 1;
GO

-- 1. Area-level rental and return activity
WITH matched_trips AS (
    SELECT
        origin_station_id,
        destination_station_id
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
      AND destination_station_id IS NOT NULL
),
rental_activity AS (
    SELECT
        s.area,
        COUNT(*) AS rental_trips
    FROM matched_trips f
    JOIN dbo.station_reference s
        ON f.origin_station_id = s.station_id
    GROUP BY
        s.area
),
return_activity AS (
    SELECT
        s.area,
        COUNT(*) AS return_trips
    FROM matched_trips f
    JOIN dbo.station_reference s
        ON f.destination_station_id = s.station_id
    GROUP BY
        s.area
)
SELECT
    COALESCE(r.area, d.area) AS area,
    COALESCE(r.rental_trips, 0) AS rental_trips,
    COALESCE(d.return_trips, 0) AS return_trips,
    COALESCE(r.rental_trips, 0)
        + COALESCE(d.return_trips, 0) AS total_activity,
    COALESCE(d.return_trips, 0)
        - COALESCE(r.rental_trips, 0) AS net_flow
FROM rental_activity r
FULL OUTER JOIN return_activity d
    ON r.area = d.area
ORDER BY
    total_activity DESC;

-- 2. Area activity normalized by active station count
WITH origin_activity AS (
    SELECT 
        origin_station_id AS station_id, 
        COUNT(*) AS rental_trips
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
        AND destination_station_id IS NOT NULL
    GROUP BY
        origin_station_id
), 
destination_activity AS (
    SELECT 
        destination_station_id AS station_id, 
        COUNT(*) AS return_trips
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
        AND destination_station_id IS NOT NULL
    GROUP BY
        destination_station_id
), 
station_activity AS (
    SELECT 
        COALESCE(o.station_id, d.station_id) AS station_id, 
        COALESCE(o.rental_trips, 0) AS rental_trips, 
        COALESCE(d.return_trips, 0) AS return_trips
    FROM origin_activity o 
    FULL OUTER JOIN destination_activity d
        ON o.station_id = d.station_id
), 
area_activity AS (
    SELECT 
        s.area, 
        COUNT(*) AS active_station_count, 
        SUM(a.rental_trips) AS rental_trips, 
        SUM(a.return_trips) AS return_trips, 
        SUM(a.rental_trips + a.return_trips) AS total_activity
    FROM station_activity a
    JOIN dbo.station_reference s
        ON a.station_id = s.station_id 
    GROUP BY 
        s.area
)
SELECT 
    area, 
    active_station_count, 
    rental_trips, 
    return_trips, 
    total_activity, 
    CAST(
        total_activity * 1.0 / active_station_count AS decimal(18, 2)
    ) AS avg_activity_per_active_station
FROM area_activity 
ORDER BY 
    avg_activity_per_active_station DESC; 

-- 3. Area share of total network activity
WITH matched_trips AS (
    SELECT 
        origin_station_id, 
        destination_station_id
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
        AND destination_station_id IS NOT NULL
), 
rental_activity AS (
    SELECT 
        s.area, 
        COUNT(*) AS rental_trips
    FROM matched_trips f
    JOIN dbo.station_reference s
        ON f.origin_station_id = s.station_id
    GROUP BY s.area
), 
return_activity AS (
    SELECT 
        s.area, 
        COUNT(*) AS return_trips
    FROM matched_trips f
    JOIN dbo.station_reference s
        ON f.destination_station_id = s.station_id
    GROUP BY s.area
), 
area_activity AS (
    SELECT 
        COALESCE(r.area, d.area) AS area, 
        COALESCE(r.rental_trips, 0) AS rental_trips,
        COALESCE(d.return_trips, 0) AS return_trips, 
        COALESCE(r.rental_trips, 0) + COALESCE(d.return_trips, 0) AS total_activity
    FROM rental_activity r
    FULL OUTER JOIN return_activity d
        ON r.area = d.area
)
SELECT 
    area, 
    rental_trips, 
    return_trips, 
    total_activity, 
    CAST(
        total_activity * 100.0 / SUM(total_activity) OVER () AS decimal(5, 2)
    ) AS network_activity_share_pct
FROM area_activity 
ORDER BY total_activity DESC; 

-- 4. Top directed flows between areas
WITH matched_trips AS (
    SELECT 
        o.area AS origin_area, 
        d.area AS destination_area
    FROM dbo.fact_trips f
    JOIN dbo.station_reference o
        ON f.origin_station_id = o.station_id
    JOIN dbo.station_reference d
        ON f.destination_station_id = d.station_id
    WHERE f.origin_station_id IS NOT NULL
        AND f.destination_station_id IS NOT NULL    
)
SELECT TOP 20
    origin_area, 
    destination_area, 
    COUNT(*) AS trip_count
FROM matched_trips
WHERE origin_area <> destination_area
GROUP BY 
    origin_area, 
    destination_area
ORDER BY 
    trip_count DESC, 
    origin_area, 
    destination_area; 

-- 5. Top area pairs by combined bidirectional flow
WITH matched_trips AS (
    SELECT 
        o.area AS origin_area, 
        d.area AS destination_area
    FROM dbo.fact_trips f
    JOIN dbo.station_reference o
        ON f.origin_station_id = o.station_id
    JOIN dbo.station_reference d
        ON f.destination_station_id = d.station_id
    WHERE f.origin_station_id IS NOT NULL
        AND f.destination_station_id IS NOT NULL    
), 
area_pairs AS (
    SELECT 
        CASE
            WHEN origin_area < destination_area
                THEN origin_area
            ELSE destination_area
        END AS area_1, 
        CASE 
            WHEN origin_area < destination_area
                THEN destination_area
            ELSE origin_area
        END AS area_2, 
        SUM(
            CASE 
                WHEN origin_area < destination_area THEN 1
                ELSE 0
            END
        ) AS area_1_to_2_trips, 
        SUM(
            CASE 
                WHEN origin_area > destination_area THEN 1
                ELSE 0
            END
        ) AS area_2_to_1_trips, 
        COUNT(*) AS total_pair_trips
    FROM matched_trips
    WHERE origin_area <> destination_area
    GROUP BY 
        CASE
            WHEN origin_area < destination_area
                THEN origin_area
            ELSE destination_area
        END, 
        CASE 
            WHEN origin_area < destination_area
                THEN destination_area
            ELSE origin_area
        END 
)
SELECT TOP 20
    area_1, 
    area_2, 
    area_1_to_2_trips, 
    area_2_to_1_trips, 
    total_pair_trips, 
    ABS(area_1_to_2_trips - area_2_to_1_trips) AS directional_difference, 
    CAST(
        ABS(area_1_to_2_trips - area_2_to_1_trips) * 100.0 / total_pair_trips AS decimal(5, 2)
    ) AS directional_imbalance_pct
FROM area_pairs
ORDER BY 
    total_pair_trips DESC, 
    area_1, 
    area_2; 