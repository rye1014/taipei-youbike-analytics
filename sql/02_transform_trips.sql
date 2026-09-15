USE TaipeiYouBikeAnalytics;
GO

SET XACT_ABORT ON;
GO

DECLARE @source_file VARCHAR(50) = '202602.csv';
DECLARE @staging_row_count INT;
DECLARE @fact_row_count INT;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 如果存在 source_file 202602.csv 就停止執行
    IF EXISTS (
        SELECT 1
        FROM dbo.fact_trips
        WHERE source_file = @source_file
    )
    BEGIN
        THROW 50001, 'dbo.fact_trips already contains rows for 202602.csv. Stop without deleting or overwriting existing fact rows.', 1;
    END;

    -- 取得總行數
    SELECT
        @staging_row_count = COUNT(*)
    FROM dbo.stg_trip_import
    WHERE source_file = @source_file;

    IF @staging_row_count = 0
    BEGIN
        THROW 50002, 'dbo.stg_trip_import contains no rows for 202602.csv. Stop without inserting fact rows.', 1;
    END;

    ;WITH source_rows AS (
        SELECT
            s.source_file,
            s.row_number_in_file,
            s.rent_time_raw,
            s.rent_station_name_raw,
            s.return_time_raw,
            s.return_station_name_raw,
            s.trip_duration_raw,
            s.bike_type_raw,
            s.info_date_raw,
            LTRIM(RTRIM(s.trip_duration_raw)) AS duration_text
        FROM dbo.stg_trip_import AS s
        WHERE s.source_file = @source_file
    ),
    duration_positions AS (
        SELECT
            source_rows.*,
            CHARINDEX(':', duration_text) AS first_colon
        FROM source_rows
    ),
    duration_colons AS (
        SELECT
            duration_positions.*,
            CASE
                WHEN first_colon > 0
                    THEN CHARINDEX(':', duration_text, first_colon + 1)
                ELSE 0
            END AS second_colon
        FROM duration_positions
    ),
    duration_components AS (
        SELECT
            duration_colons.*,
            CASE
                WHEN second_colon > 0
                    THEN CHARINDEX(':', duration_text, second_colon + 1)
                ELSE 0
            END AS third_colon,
            CASE
                WHEN first_colon > 1
                    THEN TRY_CONVERT(INT, SUBSTRING(duration_text, 1, first_colon - 1))
                ELSE NULL
            END AS duration_hours,
            CASE
                WHEN second_colon > first_colon + 1
                    THEN TRY_CONVERT(
                        INT,
                        SUBSTRING(
                            duration_text,
                            first_colon + 1,
                            second_colon - first_colon - 1
                        )
                    )
                ELSE NULL
            END AS duration_minutes,
            CASE
                WHEN second_colon > 0
                    AND LEN(duration_text) > second_colon
                    THEN TRY_CONVERT(
                        INT,
                        SUBSTRING(
                            duration_text,
                            second_colon + 1,
                            LEN(duration_text) - second_colon
                        )
                    )
                ELSE NULL
            END AS duration_seconds_component
        FROM duration_colons
    ),
    transformed_rows AS (
        SELECT
            dc.source_file,
            dc.row_number_in_file,
            TRY_CONVERT(DATETIME2(0), dc.rent_time_raw, 120) AS rent_time,  -- yyyy-mm-dd hh:mi:ss
            TRY_CONVERT(DATETIME2(0), dc.return_time_raw, 120) AS return_time,
            TRY_CONVERT(DATE, dc.info_date_raw, 23) AS info_date, -- yyyy-mm-dd
            dc.rent_station_name_raw AS origin_station_name_raw,
            dc.return_station_name_raw AS destination_station_name_raw,
            origin_station.station_id AS origin_station_id,
            destination_station.station_id AS destination_station_id,
            dc.trip_duration_raw,
            CASE
                WHEN dc.first_colon > 1
                    AND dc.second_colon > dc.first_colon + 1
                    AND dc.third_colon = 0
                    AND dc.duration_hours IS NOT NULL
                    AND dc.duration_minutes IS NOT NULL
                    AND dc.duration_seconds_component IS NOT NULL
                    AND dc.duration_hours >= 0
                    AND dc.duration_minutes BETWEEN 0 AND 59
                    AND dc.duration_seconds_component BETWEEN 0 AND 59
                    THEN
                        dc.duration_hours * 3600
                        + dc.duration_minutes * 60
                        + dc.duration_seconds_component
                ELSE NULL
            END AS trip_duration_seconds,
            dc.bike_type_raw AS bike_type,
            CASE
                WHEN dc.first_colon > 1
                    AND dc.second_colon > dc.first_colon + 1
                    AND dc.third_colon = 0
                    AND dc.duration_hours IS NOT NULL
                    AND dc.duration_minutes IS NOT NULL
                    AND dc.duration_seconds_component IS NOT NULL
                    AND dc.duration_hours >= 0
                    AND dc.duration_minutes BETWEEN 0 AND 59
                    AND dc.duration_seconds_component BETWEEN 0 AND 59
                    THEN CAST(0 AS BIT)
                ELSE CAST(1 AS BIT)
            END AS duration_parse_failed,
            -- 判斷編碼
            CASE
                WHEN CHARINDEX(
                    N'?',
                    dc.rent_station_name_raw COLLATE Latin1_General_100_BIN2
                ) > 0
                OR CHARINDEX(
                    NCHAR(65533),
                    dc.rent_station_name_raw COLLATE Latin1_General_100_BIN2
                ) > 0
                THEN CAST(1 AS BIT)
                ELSE CAST(0 AS BIT)
            END AS origin_name_degraded, 
            CASE
                WHEN CHARINDEX(
                    N'?',
                    dc.return_station_name_raw COLLATE Latin1_General_100_BIN2
                ) > 0
                OR CHARINDEX(
                    NCHAR(65533),
                    dc.return_station_name_raw COLLATE Latin1_General_100_BIN2
                ) > 0
                THEN CAST(1 AS BIT)
                ELSE CAST(0 AS BIT)
            END AS destination_name_degraded
        FROM duration_components AS dc
        LEFT JOIN dbo.station_reference AS origin_station
            ON dc.rent_station_name_raw = origin_station.station_name
        LEFT JOIN dbo.station_reference AS destination_station
            ON dc.return_station_name_raw = destination_station.station_name
    )
    INSERT INTO dbo.fact_trips (
        source_file,
        row_number_in_file,
        rent_time,
        return_time,
        info_date,
        origin_station_name_raw,
        destination_station_name_raw,
        origin_station_id,
        destination_station_id,
        trip_duration_raw,
        trip_duration_seconds,
        bike_type,
        duration_parse_failed,
        origin_name_degraded,
        destination_name_degraded
    )
    SELECT
        source_file,
        row_number_in_file,
        rent_time,
        return_time,
        info_date,
        origin_station_name_raw,
        destination_station_name_raw,
        origin_station_id,
        destination_station_id,
        trip_duration_raw,
        trip_duration_seconds,
        bike_type,
        duration_parse_failed,
        origin_name_degraded,
        destination_name_degraded
    FROM transformed_rows;

    SELECT
        @fact_row_count = COUNT(*)
    FROM dbo.fact_trips
    WHERE source_file = @source_file;

    IF @fact_row_count <> @staging_row_count
    BEGIN
        THROW 50003, 'Fact row count does not match staging row count for 202602.csv. Rolling back transformation.', 1;
    END;

    COMMIT TRANSACTION;

    SELECT
        @source_file AS source_file,
        @staging_row_count AS staging_row_count,
        @fact_row_count AS fact_row_count,
        'success' AS status;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;
GO
