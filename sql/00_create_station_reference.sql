USE TaipeiYouBikeAnalytics;
GO

CREATE TABLE dbo.station_reference (
    station_id VARCHAR(20) NOT NULL,
    station_name_raw NVARCHAR(200) NOT NULL,
    station_name NVARCHAR(200) NOT NULL,
    area NVARCHAR(100) NULL,
    address NVARCHAR(300) NULL,
    latitude DECIMAL(9,6) NULL,
    longitude DECIMAL(10,6) NULL,
    capacity INT NULL,
    snapshot_date DATE NOT NULL,

    CONSTRAINT PK_station_reference
        PRIMARY KEY (station_id)
);
GO