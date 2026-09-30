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


-------------------------------------------------------

-- 7. Station activity and directional imbalance
CREATE OR ALTER VIEW dbo.vw_station_activity AS 

WITH rental_activity AS (
    SELECT 
        origin_station_id AS station_id, 
        COUNT_BIG(*) AS rental_trips
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
    GROUP BY origin_station_id
), 
return_activity AS (
    SELECT
        destination_station_id AS station_id, 
        COUNT_BIG(*) AS return_trips
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
    GROUP BY destination_station_id
), 
station_activity AS (
    SELECT 
        COALESCE(r.station_id, d.station_id) AS station_id, 
        COALESCE(r.rental_trips, 0) AS rental_trips, 
        COALESCE(d.return_trips, 0) AS return_trips
    FROM rental_activity r
    FULL OUTER JOIN return_activity d
        ON r.station_id = d.station_id
)
SELECT 
    a.station_id, 
    s.station_name, 
    s.area, 
    a.rental_trips, 
    a.return_trips, 
    a.rental_trips + a.return_trips AS total_activity, 
    a.return_trips - a.rental_trips AS net_flow, 
    ABS(a.return_trips - a.rental_trips) AS absolute_imbalance, 
    CAST(
        ABS(a.return_trips - a.rental_trips) * 100.0 / NULLIF(a.rental_trips + a.return_trips, 0) AS decimal(6, 2)
    ) AS relative_imbalance_pct
FROM station_activity a
JOIN dbo.station_reference s
    ON a.station_id = s.station_id; 
GO

-- 8. Station hourly flow
CREATE OR ALTER VIEW dbo.vw_station_hourly_flow AS 

WITH hours AS (
    SELECT hour_of_day
    FROM (
        VALUES 
            (0), (1), (2), (3), (4), (5), 
            (6), (7), (8), (9), (10), (11), 
            (12), (13), (14), (15), (16), (17), 
            (18), (19), (20), (21), (22), (23)
    ) AS h(hour_of_day)
), 
active_stations AS (
    SELECT 
        station_id, 
        station_name, 
        area
    FROM dbo.vw_station_activity
), 
rental_hourly AS (
    SELECT 
        origin_station_id AS station_id, 
        DATEPART(hour, rent_time) AS hour_of_day, 
        COUNT_BIG(*) AS rental_trips
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL
        AND rent_time IS NOT NULL
    GROUP BY 
        origin_station_id, 
        DATEPART(hour, rent_time)
), 
return_hourly AS (
    SELECT 
        destination_station_id AS station_id, 
        DATEPART(hour, return_time) AS hour_of_day, 
        COUNT_BIG(*) AS return_trips
    FROM dbo.fact_trips
    WHERE destination_station_id IS NOT NULL
        AND return_time IS NOT NULL
    GROUP BY 
        destination_station_id, 
        DATEPART(hour, return_time)
)
SELECT 
    s.station_id, 
    s.station_name, 
    s.area, 
    h.hour_of_day, 
    COALESCE(r.rental_trips, 0) AS rental_trips, 
    COALESCE(d.return_trips, 0) AS return_trips, 
    COALESCE(r.rental_trips, 0) + COALESCE(d.return_trips, 0) AS total_activity, 
    COALESCE(d.return_trips, 0) - COALESCE(r.rental_trips, 0) AS net_flow
FROM active_stations s
CROSS JOIN hours AS h
LEFT JOIN rental_hourly AS r
    ON s.station_id = r.station_id
        AND h.hour_of_day = r.hour_of_day
LEFT JOIN return_hourly AS d
    ON s.station_id = d.station_id
        AND h.hour_of_day = d.hour_of_day; 
GO

-- 9. Station peak-period flow
CREATE OR ALTER VIEW dbo.vw_station_peak_flow AS 

WITH peak_hours AS (
    SELECT 
        station_id, 
        station_name, 
        area, 
        CASE
            WHEN hour_of_day BETWEEN 7 AND 9
                THEN 'Morning'
            WHEN hour_of_day BETWEEN 17 AND 19
                THEN 'Evening'
        END AS peak_period, 
        rental_trips, 
        return_trips
    FROM dbo.vw_station_hourly_flow
    WHERE hour_of_day BETWEEN 7 AND 9
        OR hour_of_day BETWEEN 17 AND 19
)
SELECT 
    station_id, 
    station_name, 
    area, 
    peak_period, 
    SUM(rental_trips) AS rental_trips, 
    SUM(return_trips) AS return_trips, 
    SUM(rental_trips) + SUM(return_trips) AS total_activity, 
    SUM(return_trips) - SUM(rental_trips) AS net_flow
FROM peak_hours
GROUP BY 
    station_id, 
    station_name, 
    area, 
    peak_period; 
GO


-------------------------------------------------------


-- 10. Directed OD route summary
CREATE OR ALTER VIEW dbo.vw_od_routes AS 

SELECT 
    f.origin_station_id, 
    o.station_name AS origin_station_name, 
    o.area AS origin_area, 
    f.destination_station_id, 
    d.station_name AS destination_station_name, 
    d.area AS destination_area, 
    COUNT_BIG(*) AS trip_count
FROM dbo.fact_trips f
JOIN dbo.station_reference o
    ON f.origin_station_id = o.station_id
JOIN dbo.station_reference d
    ON f.destination_station_id = d.station_id 
WHERE f.origin_station_id IS NOT NULL
    AND f.destination_station_id IS NOT NULL
    AND f.origin_station_id <> f.destination_station_id
GROUP BY 
    f.origin_station_id, 
    o.station_name, 
    o.area, 
    f.destination_station_id, 
    d.station_name, 
    d.area; 
GO

-- 11. Bidirectional station pair summary
CREATE OR ALTER VIEW dbo.vw_station_pairs AS 

WITH pair_activity AS (
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
                    THEN trip_count
                ELSE 0
            END
        ) AS station_1_to_2_trips, 
        SUM(
            CASE 
                WHEN origin_station_id > destination_station_id 
                    THEN trip_count
                ELSE 0
            END
        ) AS station_2_to_1_trips
    FROM dbo.vw_od_routes
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
SELECT
    p.station_1_id, 
    s1.station_name AS station_1_name, 
    s1.area AS station_1_area, 
    p.station_2_id, 
    s2.station_name AS station_2_name, 
    s2.area AS station_2_area, 
    p.station_1_to_2_trips, 
    p.station_2_to_1_trips, 
    p.station_1_to_2_trips + p.station_2_to_1_trips AS total_pair_trips, 
    ABS(
        p.station_1_to_2_trips - p.station_2_to_1_trips
    ) AS directional_difference, 
    CAST(
        ABS(
            p.station_1_to_2_trips - p.station_2_to_1_trips
        ) * 100.0 
        / NULLIF(
            p.station_1_to_2_trips + p.station_2_to_1_trips, 0
        ) AS decimal(6, 2)
    ) AS directional_imbalance_pct
FROM pair_activity p
JOIN dbo.station_reference s1
    ON p.station_1_id = s1.station_id
JOIN dbo.station_reference s2
    ON p.station_2_id = s2.station_id; 
GO

-- 12. Peak-period directed OD routes
CREATE OR ALTER VIEW dbo.vw_peak_od_routes AS 

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
    COUNT_BIG(*) AS trip_count
FROM dbo.fact_trips f
JOIN dbo.station_reference o
    ON f.origin_station_id = o.station_id 
JOIN dbo.station_reference d
    ON f.destination_station_id = d.station_id
WHERE f.origin_station_id IS NOT NULL
    AND f.destination_station_id IS NOT NULL
    AND f.origin_station_id <> f.destination_station_id
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
    d.area; 
GO

-- 13. Weekday/weekend directed OD routes
CREATE OR ALTER VIEW dbo.vw_day_type_od_routes AS

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
route_counts AS (
    SELECT
        CASE
            WHEN DATEDIFF(
                day,
                '19000101',
                CAST(f.rent_time AS date)
            ) % 7 BETWEEN 0 AND 4
                THEN 'Weekday'
            ELSE 'Weekend'
        END AS day_type,

        f.origin_station_id,
        o.station_name AS origin_station_name,
        o.area AS origin_area,

        f.destination_station_id,
        d.station_name AS destination_station_name,
        d.area AS destination_area,

        COUNT_BIG(*) AS trip_count

    FROM dbo.fact_trips AS f

    JOIN dbo.station_reference AS o
        ON f.origin_station_id = o.station_id

    JOIN dbo.station_reference AS d
        ON f.destination_station_id = d.station_id

    WHERE f.origin_station_id IS NOT NULL
      AND f.destination_station_id IS NOT NULL
      AND f.origin_station_id <> f.destination_station_id
      AND f.rent_time IS NOT NULL

    GROUP BY
        CASE
            WHEN DATEDIFF(
                day,
                '19000101',
                CAST(f.rent_time AS date)
            ) % 7 BETWEEN 0 AND 4
                THEN 'Weekday'
            ELSE 'Weekend'
        END,
        f.origin_station_id,
        o.station_name,
        o.area,
        f.destination_station_id,
        d.station_name,
        d.area
)
SELECT
    r.day_type,
    r.origin_station_id,
    r.origin_station_name,
    r.origin_area,
    r.destination_station_id,
    r.destination_station_name,
    r.destination_area,
    r.trip_count,
    d.number_of_days,
    CAST(
        r.trip_count * 1.0 / d.number_of_days
        AS decimal(18,2)
    ) AS avg_daily_trips
FROM route_counts AS r
JOIN day_counts AS d
    ON r.day_type = d.day_type;
GO

-- 14. Area activity summary
CREATE OR ALTER VIEW dbo.vw_area_activity AS 

WITH origin_activity AS (
    SELECT 
        origin_station_id AS station_id, 
        COUNT_BIG(*) AS rental_trips
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL 
        AND destination_station_id IS NOT NULL
    GROUP BY origin_station_id
), 
destination_activity AS (
    SELECT 
        destination_station_id AS station_id, 
        COUNT_BIG(*) AS return_trips
    FROM dbo.fact_trips
    WHERE origin_station_id IS NOT NULL 
        AND destination_station_id IS NOT NULL
    GROUP BY destination_station_id
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
        COUNT_BIG(*) AS active_station_count, 
        SUM(a.rental_trips) AS rental_trips, 
        SUM(a.return_trips) AS return_trips, 
        SUM(a.rental_trips + a.return_trips) AS total_activity 
    FROM station_activity a
    JOIN dbo.station_reference s
        ON a.station_id = s.station_id
    GROUP BY s.area
)
SELECT 
    area, 
    active_station_count, 
    rental_trips, 
    return_trips, 
    total_activity, 
    return_trips - rental_trips AS net_flow, 
    CAST(
        total_activity * 1.0 / active_station_count AS decimal(18, 2)
    ) AS avg_activity_per_active_station, 
    CAST(
        total_activity * 100.0 / SUM(total_activity) OVER () AS decimal(5, 2)
    ) AS network_activity_share_pct
FROM area_activity; 
GO

-- 15. Directed area-to-area flows
CREATE OR ALTER VIEW dbo.vw_area_flows AS 

SELECT 
    o.area AS origin_area, 
    d.area AS destination_area, 
    COUNT_BIG(*) AS trip_count
FROM dbo.fact_trips f
JOIN dbo.station_reference o
    ON f.origin_station_id = o.station_id 
JOIN dbo.station_reference d
    ON f.destination_station_id = d.station_id 
WHERE f.origin_station_id IS NOT NULL
    AND f.destination_station_id IS NOT NULL
    AND o.area <> d.area 
GROUP BY 
    o.area, 
    d.area; 
GO

-- 16. Bidirectional area pair summary
CREATE OR ALTER VIEW dbo.vw_area_pairs AS 

WITH pair_activity AS (
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
                WHEN origin_area < destination_area
                    THEN trip_count
                ELSE 0
            END
        ) AS area_1_to_2_trips, 
        SUM(
            CASE
                WHEN origin_area > destination_area
                    THEN trip_count
                ELSE 0
            END
        ) AS area_2_to_1_trips
    FROM dbo.vw_area_flows
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
SELECT 
    area_1, 
    area_2, 
    area_1_to_2_trips, 
    area_2_to_1_trips, 
    area_1_to_2_trips + area_2_to_1_trips AS total_pair_trips, 
    ABS(
        area_1_to_2_trips - area_2_to_1_trips
    ) AS directional_difference, 
    CAST(
        ABS(
            area_1_to_2_trips - area_2_to_1_trips
        ) * 100.0 
        / NULLIF(
            area_1_to_2_trips + area_2_to_1_trips, 0
        ) AS decimal(6, 2)
    ) AS directional_imbalance_pct
FROM pair_activity; 
GO