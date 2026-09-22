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