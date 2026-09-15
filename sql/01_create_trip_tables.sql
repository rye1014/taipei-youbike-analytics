USE TaipeiYouBikeAnalytics;
GO


/* =========================================================
   1. Staging table
   Temporarily holds one raw monthly CSV during ingestion.
   ========================================================= */

CREATE TABLE dbo.stg_trip_import (

    source_file VARCHAR(50) NOT NULL,
    row_number_in_file INT NOT NULL,

    rent_time_raw VARCHAR(30) NULL,
    rent_station_name_raw NVARCHAR(200) NULL,

    return_time_raw VARCHAR(30) NULL,
    return_station_name_raw NVARCHAR(200) NULL,

    trip_duration_raw VARCHAR(20) NULL,
    bike_type_raw NVARCHAR(20) NULL,
    info_date_raw VARCHAR(20) NULL,

    CONSTRAINT CK_stg_trip_import_row_number_positive
        CHECK (row_number_in_file > 0),

    CONSTRAINT CK_stg_trip_import_source_file_format
        CHECK (
            source_file LIKE '[12][0-9][0-9][0-9][01][0-9].csv'
            AND SUBSTRING(source_file, 5, 2) BETWEEN '01' AND '12'
        )
);
GO


/* =========================================================
   2. Fact table
   Cleaned and transformed trip-level analytical data.
   ========================================================= */

CREATE TABLE dbo.fact_trips (

    source_file VARCHAR(50) NOT NULL,
    row_number_in_file INT NOT NULL,

    rent_time DATETIME2(0) NULL,
    return_time DATETIME2(0) NULL,
    info_date DATE NULL,

    origin_station_name_raw NVARCHAR(200) NULL,
    destination_station_name_raw NVARCHAR(200) NULL,

    origin_station_id VARCHAR(20) NULL,
    destination_station_id VARCHAR(20) NULL,

    trip_duration_raw VARCHAR(20) NULL,
    trip_duration_seconds INT NULL,

    bike_type NVARCHAR(20) NULL,

    duration_parse_failed BIT NOT NULL,
    origin_name_degraded BIT NOT NULL,
    destination_name_degraded BIT NOT NULL,

    CONSTRAINT PK_fact_trips
        PRIMARY KEY NONCLUSTERED (
            source_file,
            row_number_in_file
        ),

    CONSTRAINT CK_fact_trips_row_number_positive
        CHECK (row_number_in_file > 0),

    CONSTRAINT CK_fact_trips_source_file_format
        CHECK (
            source_file LIKE '[12][0-9][0-9][0-9][01][0-9].csv'
            AND SUBSTRING(source_file, 5, 2) BETWEEN '01' AND '12'
        ),

    CONSTRAINT CK_fact_trips_duration_non_negative
        CHECK (
            trip_duration_seconds IS NULL
            OR trip_duration_seconds >= 0
        )
);
GO


/* =========================================================
   3. ETL load log
   Keeps one record for every load attempt.
   The same source_file may appear multiple times.
   ========================================================= */

CREATE TABLE dbo.etl_trip_load_log (

    load_log_id BIGINT IDENTITY(1,1) NOT NULL,

    source_file VARCHAR(50) NOT NULL,

    source_row_count INT NULL,
    loaded_row_count INT NULL,
    duration_parse_failures INT NULL,

    loaded_at_utc DATETIME2(0) NOT NULL
        CONSTRAINT DF_etl_trip_load_log_loaded_at_utc
        DEFAULT (SYSUTCDATETIME()),

    status VARCHAR(30) NOT NULL,

    error_message NVARCHAR(1000) NULL,

    CONSTRAINT PK_etl_trip_load_log
        PRIMARY KEY (load_log_id),

    CONSTRAINT CK_etl_trip_load_log_source_file_format
        CHECK (
            source_file LIKE '[12][0-9][0-9][0-9][01][0-9].csv'
            AND SUBSTRING(source_file, 5, 2) BETWEEN '01' AND '12'
        ),

    CONSTRAINT CK_etl_trip_load_log_source_row_count_non_negative
        CHECK (
            source_row_count IS NULL
            OR source_row_count >= 0
        ),

    CONSTRAINT CK_etl_trip_load_log_loaded_row_count_non_negative
        CHECK (
            loaded_row_count IS NULL
            OR loaded_row_count >= 0
        ),

    CONSTRAINT CK_etl_trip_load_log_duration_failures_non_negative
        CHECK (
            duration_parse_failures IS NULL
            OR duration_parse_failures >= 0
        ),

    CONSTRAINT CK_etl_trip_load_log_status
        CHECK (
            status IN ('success', 'failed', 'partial')
        )
);
GO