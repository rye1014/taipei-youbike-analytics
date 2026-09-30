USE TaipeiYouBikeAnalytics;
GO

-- Mon = 1, Sun = 7
SET DATEFIRST 1;
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

-- 6. Top OD routes during morning and evening peak periods
-- Peak period: 
--   Morning: 7:00 - 9:00
--   Evening: 17:00 - 19:00
WITH peak_routes AS (
    SELECT 
        CASE  
            WHEN DATEPART(hour, f.rent_time) BETWEEN 7 AND 9
                THEN 'Morning'
            WHEN DATEPART(hour, f.rent_time) BETWEEN 17 AND 19
                THEN 'Evening'
        END AS peak_period, 

        f.origin_station_id, 
        o.station_name AS origin_station_name, 
        o.area AS origin_area, 

        f.destination_station_id, 
        d.station_name AS destination_station_name, 
        d.area AS destination_area, 

        COUNT(*) AS trip_count

    FROM dbo.fact_trips f
    JOIN dbo.station_reference o
        ON f.origin_station_id = o.station_id
    JOIN dbo.station_reference d 
        ON f.destination_station_id = d.station_id

    WHERE f.origin_station_id <> f.destination_station_id 
        AND (
            DATEPART(hour, f.rent_time) BETWEEN 7 AND 9
            OR DATEPART(hour, f.rent_time) BETWEEN 17 AND 19
        )
    
    GROUP BY 
        CASE  
            WHEN DATEPART(hour, f.rent_time) BETWEEN 7 AND 9
                THEN 'Morning'
            WHEN DATEPART(hour, f.rent_time) BETWEEN 17 AND 19
                THEN 'Evening'
        END, 
        f.origin_station_id, 
        o.station_name, 
        o.area, 
        f.destination_station_id, 
        d.station_name, 
        d.area
), 
ranked_routes AS (
    SELECT
        *, 
        ROW_NUMBER() OVER (
            PARTITION BY peak_period
            ORDER BY 
                trip_count DESC, 
                origin_station_id, 
                destination_station_id
        ) AS route_rank
    FROM peak_routes
)
SELECT 
    peak_period, 
    route_rank, 
    origin_station_id, 
    origin_station_name, 
    origin_area, 
    destination_station_id, 
    destination_station_name, 
    destination_area, 
    trip_count
FROM ranked_routes 
WHERE route_rank <= 20
ORDER BY 
    CASE peak_period 
        WHEN 'Morning' THEN 1 
        WHEN 'Evening' THEN 2
    END, 
    route_rank; 

-- 7. Morning-to-evening reverse-route overlap
WITH peak_routes AS (
    SELECT 
        CASE  
            WHEN DATEPART(hour, f.rent_time) BETWEEN 7 AND 9
                THEN 'Morning'
            WHEN DATEPART(hour, f.rent_time) BETWEEN 17 AND 19
                THEN 'Evening'
        END AS peak_period, 

        f.origin_station_id, 
        o.station_name AS origin_station_name, 
        o.area AS origin_area, 

        f.destination_station_id, 
        d.station_name AS destination_station_name, 
        d.area AS destination_area, 

        COUNT(*) AS trip_count

    FROM dbo.fact_trips f
    JOIN dbo.station_reference o
        ON f.origin_station_id = o.station_id
    JOIN dbo.station_reference d 
        ON f.destination_station_id = d.station_id

    WHERE f.origin_station_id <> f.destination_station_id 
        AND (
            DATEPART(hour, f.rent_time) BETWEEN 7 AND 9
            OR DATEPART(hour, f.rent_time) BETWEEN 17 AND 19
        )
    
    GROUP BY 
        CASE  
            WHEN DATEPART(hour, f.rent_time) BETWEEN 7 AND 9
                THEN 'Morning'
            WHEN DATEPART(hour, f.rent_time) BETWEEN 17 AND 19
                THEN 'Evening'
        END, 
        f.origin_station_id, 
        o.station_name, 
        o.area, 
        f.destination_station_id, 
        d.station_name, 
        d.area
), 
ranked_routes AS (
    SELECT
        *, 
        ROW_NUMBER() OVER (
            PARTITION BY peak_period
            ORDER BY 
                trip_count DESC, 
                origin_station_id, 
                destination_station_id
        ) AS route_rank
    FROM peak_routes
), 
morning_top20 AS (
    SELECT * 
    FROM ranked_routes 
    WHERE peak_period = 'Morning'
        AND route_rank <= 20
), 
evening_top20 AS (
    SELECT * 
    FROM ranked_routes 
    WHERE peak_period = 'Evening'
        AND route_rank <= 20
)
SELECT 
    m.route_rank AS morning_rank, 
    m.origin_station_name AS morning_origin, 
    m.destination_station_name AS morning_destination, 
    m.trip_count AS morning_trip_count, 

    e.route_rank AS evening_reverse_rank, 
    e.trip_count AS evening_reverse_trip_count, 

    CASE 
        WHEN e.route_rank IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS reverse_in_evening_top20

FROM morning_top20 m
LEFT JOIN evening_top20 e
    ON m.origin_station_id = e.destination_station_id 
    AND m.destination_station_id = e.origin_station_id
ORDER BY m.route_rank; 

-- 8. Top OD routes on weekdays and weekends
WITH day_counts AS (
    SELECT 
        CASE 
            WHEN DATEPART(weekday, rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type, 
        COUNT(DISTINCT CAST(rent_time AS date)) AS number_of_days
    FROM dbo.fact_trips
    GROUP BY 
        CASE 
            WHEN DATEPART(weekday, rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END
), 
route_counts AS (
    SELECT 
        CASE 
            WHEN DATEPART(weekday, f.rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type, 

        f.origin_station_id, 
        o.station_name AS origin_station_name, 
        o.area AS origin_area, 
        f.destination_station_id, 
        d.station_name AS destination_station_name, 
        d.area AS destination_area, 

        COUNT(*) AS trip_count

    FROM dbo.fact_trips f
    JOIN dbo.station_reference o
        ON f.origin_station_id = o.station_id
    JOIN dbo.station_reference d
        ON f.destination_station_id = d.station_id

    WHERE f.origin_station_id <> f.destination_station_id 

    GROUP BY 
        CASE 
            WHEN DATEPART(weekday, f.rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END, 
        f.origin_station_id, 
        o.station_name, 
        o.area, 
        f.destination_station_id, 
        d.station_name, 
        d.area
), 
route_averages AS (
    SELECT 
        r.day_type, 
        r.origin_station_id, 
        r.origin_station_name, 
        r.origin_area, 
        r.destination_station_id, 
        r.destination_station_name, 
        r.destination_area, 
        r.trip_count, 
        CAST(
            r.trip_count * 1.0 / d.number_of_days AS decimal(18, 2)
        ) AS avg_daily_trips
    FROM route_counts r 
    JOIN day_counts d
        ON r.day_type = d.day_type
), 
ranked_routes AS (
    SELECT 
        *, 
        ROW_NUMBER() OVER (
            PARTITION BY day_type
            ORDER BY
                trip_count DESC,
                origin_station_id,
                destination_station_id
        ) AS route_rank
    FROM route_averages
)
SELECT 
    day_type, 
    route_rank, 
    origin_station_id, 
    origin_station_name, 
    origin_area, 
    destination_station_id, 
    destination_station_name, 
    destination_area,
    trip_count, 
    avg_daily_trips
FROM ranked_routes 
WHERE route_rank <= 20
ORDER BY 
    CASE day_type
        WHEN 'Weekday' THEN 1
        WHEN 'Weekend' THEN 2
    END, 
    route_rank; 

-- 9. Weekday-to-weekend top 20 route overlap
WITH day_counts AS (
    SELECT 
        CASE 
            WHEN DATEPART(weekday, rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type, 
        COUNT(DISTINCT CAST(rent_time AS date)) AS number_of_days
    FROM dbo.fact_trips
    GROUP BY 
        CASE 
            WHEN DATEPART(weekday, rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END
), 
route_counts AS (
    SELECT 
        CASE 
            WHEN DATEPART(weekday, f.rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type, 

        f.origin_station_id, 
        o.station_name AS origin_station_name, 
        o.area AS origin_area, 
        f.destination_station_id, 
        d.station_name AS destination_station_name, 
        d.area AS destination_area, 

        COUNT(*) AS trip_count

    FROM dbo.fact_trips f
    JOIN dbo.station_reference o
        ON f.origin_station_id = o.station_id
    JOIN dbo.station_reference d
        ON f.destination_station_id = d.station_id

    WHERE f.origin_station_id <> f.destination_station_id 

    GROUP BY 
        CASE 
            WHEN DATEPART(weekday, f.rent_time) BETWEEN 1 AND 5
                THEN 'Weekday'
            ELSE 'Weekend'
        END, 
        f.origin_station_id, 
        o.station_name, 
        o.area, 
        f.destination_station_id, 
        d.station_name, 
        d.area
), 
route_averages AS (
    SELECT 
        r.day_type, 
        r.origin_station_id, 
        r.origin_station_name, 
        r.origin_area, 
        r.destination_station_id, 
        r.destination_station_name, 
        r.destination_area, 
        r.trip_count, 
        CAST(
            r.trip_count * 1.0 / d.number_of_days AS decimal(18, 2)
        ) AS avg_daily_trips
    FROM route_counts r 
    JOIN day_counts d
        ON r.day_type = d.day_type
), 
ranked_routes AS (
    SELECT 
        *, 
        ROW_NUMBER() OVER (
            PARTITION BY day_type
            ORDER BY
                trip_count DESC,
                origin_station_id,
                destination_station_id
        ) AS route_rank
    FROM route_averages
), 
weekday_top20 AS (
    SELECT * 
    FROM ranked_routes 
    WHERE day_type = 'Weekday'
        AND route_rank <= 20
), 
weekend_top20 AS (
    SELECT * 
    FROM ranked_routes 
    WHERE day_type = 'Weekend'
        AND route_rank <= 20
)
SELECT 
    COUNT(*) AS overlapping_routes, 
    CAST(COUNT(*) * 100.0 / 20 AS decimal(5, 2)) AS overlap_pct
FROM weekday_top20 AS w
JOIN weekend_top20 AS e
    ON w.origin_station_id = e.origin_station_id 
        AND w.destination_station_id = e.destination_station_id; 