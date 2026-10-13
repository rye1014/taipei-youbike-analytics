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