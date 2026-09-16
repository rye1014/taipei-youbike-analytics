SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    YEAR(rent_time) AS rent_year,
    MONTH(rent_time) AS rent_month,
    COUNT(*) AS trip_count
FROM dbo.fact_trips
GROUP BY
    YEAR(rent_time),
    MONTH(rent_time)
ORDER BY
    rent_year,
    rent_month;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;