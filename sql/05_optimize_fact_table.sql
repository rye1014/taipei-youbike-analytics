USE TaipeiYouBikeAnalytics;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.fact_trips')
      AND name = N'CCI_fact_trips'
)
BEGIN
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_trips
    ON dbo.fact_trips;
END;
GO