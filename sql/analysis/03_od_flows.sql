USE TaipeiYouBikeAnalytics;
GO

-- 1. Top OD routes
SELECT TOP 20
    o.station_id AS origin_station_id,
    o.station_name AS origin_station_name, 
    o.area AS origin_area, 
    d.station_id AS destination_station_id, 
    d.station_name AS destination_station_name, 
    d.area AS destination_area, 
    COUNT(*) as trip_count
FROM dbo.fact_trips f
JOIN dbo.station_reference o
    ON f.origin_station_id = o.station_id 
JOIN dbo.station_reference d
    ON f.destination_station_id = d.station_id
GROUP BY 
    o.station_id, 
    o.station_name, 
    o.area, 
    d.station_id, 
    d.station_name, 
    d.area
ORDER BY 
    trip_count DESC, 
    o.station_id, 
    d.station_id; 

-- 2. Same-station vs different-station trips
SELECT 
    CASE 
        WHEN origin_station_id = destination_station_id
            THEN 'Same station'
        ELSE 'Different station'
    END AS trip_type, 
    COUNT(*) AS trip_count, 
    CAST(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS decimal(5, 2)
    ) AS trip_share_pct
FROM dbo.fact_trips
WHERE origin_station_id IS NOT NULL 
    AND destination_station_id IS NOT NULL 
GROUP BY 
    CASE 
        WHEN origin_station_id = destination_station_id 
            THEN 'Same station'
        ELSE 'Different station'
    END 
ORDER BY trip_count DESC; 

-- 3. Top stations for same-station trips
SELECT TOP 20
    s.station_id, 
    s.station_name, 
    s.area, 
    COUNT(*) AS same_station_trip_count 
FROM dbo.fact_trips f
JOIN dbo.station_reference s
    ON f.origin_station_id = s.station_id 
WHERE f.origin_station_id IS NOT NULL 
    AND f.destination_station_id IS NOT NULL 
    AND f.origin_station_id = f.destination_station_id 
GROUP BY 
    s.station_id, 
    s.station_name, 
    s.area 
ORDER BY 
    same_station_trip_count DESC, 
    s.station_id; 

-- 4. Top inter-station OD routes
SELECT TOP 20
    o.station_id AS origin_station_id,
    o.station_name AS origin_station_name, 
    o.area AS origin_area, 
    d.station_id AS destination_station_id, 
    d.station_name AS destination_station_name, 
    d.area AS destination_area, 
    COUNT(*) as trip_count
FROM dbo.fact_trips f
JOIN dbo.station_reference o
    ON f.origin_station_id = o.station_id 
JOIN dbo.station_reference d
    ON f.destination_station_id = d.station_id
WHERE f.origin_station_id <> f.destination_station_id
GROUP BY 
    o.station_id, 
    o.station_name, 
    o.area, 
    d.station_id, 
    d.station_name, 
    d.area
ORDER BY 
    trip_count DESC, 
    o.station_id, 
    d.station_id; 

-- 5. Top station pairs 
WITH pair_trips AS (
    SELECT 
        CASE 
            WHEN origin_station_id < destination_station_id 
                THEN origin_station_id 
            ELSE destination_station_id 
        END AS station_1_id,
        CASE 
            WHEN origin_station_id < destination_station_id 
                THEN destination_station_id 
            ELSE origin_station_id 
        END AS station_2_id, 
        SUM(
            CASE 
                WHEN origin_station_id < destination_station_id 
                    THEN 1 
                ELSE 0
            END
        ) AS station_1_to_2_trips, 
        SUM(
            CASE
                WHEN origin_station_id > destination_station_id 
                    THEN 1 
                ELSE 0
            END
        ) AS station_2_to_1_trips, 
        COUNT(*) AS total_pair_trips

    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
        AND destination_station_id IS NOT NULL
        AND origin_station_id <> destination_station_id
    GROUP BY 
        CASE
            WHEN origin_station_id < destination_station_id
                THEN origin_station_id
            ELSE destination_station_id
        END,
        CASE
            WHEN origin_station_id < destination_station_id
                THEN destination_station_id
            ELSE origin_station_id
        END
)
SELECT TOP 20
    p.station_1_id, 
    s1.station_name AS station_1_name, 
    s1.area AS station_1_area, 
    p.station_2_id, 
    s2.station_name AS station_2_name, 
    s2.area AS station_2_area, 
    p.station_1_to_2_trips, 
    p.station_2_to_1_trips, 
    p.total_pair_trips, 
    ABS(
        p.station_1_to_2_trips - p.station_2_to_1_trips
    ) AS directional_difference, 
    CAST(
        ABS(
            p.station_1_to_2_trips - p.station_2_to_1_trips
        ) * 100.0 / p.total_pair_trips AS decimal(5, 2)
    ) AS directional_imbalance_pct
FROM pair_trips p
JOIN dbo.station_reference s1
    ON p.station_1_id = s1.station_id 
JOIN dbo.station_reference s2
    ON p.station_2_id = s2.station_id
ORDER BY 
    p.total_pair_trips DESC, 
    p.station_1_id, 
    p.station_2_id; 