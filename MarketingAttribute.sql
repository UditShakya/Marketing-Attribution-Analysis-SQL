/*
Purpose: Clean multi-channel touchpoint logs, compute attribution credits
for First-touch, Last-touch, Linear, and Time-decay models per channel,
then join to channel cost/revenue inputs to compute ROI and cost-per-conversion.
Replace the sample channel cost/revenue data with your authoritative sources.
*/

-- Replace these sample tables with your real cost and revenue sources (use two-part names)
DECLARE @ChannelCosts TABLE (Channel nvarchar(256) NOT NULL, TotalCost decimal(18,2) NOT NULL);
DECLARE @ChannelRevenue TABLE (Channel nvarchar(256) NOT NULL, TotalRevenue decimal(18,2) NOT NULL);

-- Example data: remove or replace with SELECT ... FROM your_cost_table
INSERT INTO @ChannelCosts (Channel, TotalCost) VALUES
('display ads', 25000.00),
('direct traffic', 18000.00),
('referral', 12000.00),
('social media',15000.00),
('email',9000.00),
('search ads',20000.00);

INSERT INTO @ChannelRevenue (Channel, TotalRevenue) VALUES
('display ads', 125000.00),
('direct traffic', 98000.00),
('referral', 60000.00),
('social media',90000.00),
('email',70000.00),
('search ads',110000.00);

WITH NormalizedTouches AS (
    -- normalize channel and conversion text
    SELECT
        [User_ID],
        [Timestamp],
        CASE WHEN TRY_CAST(Channel AS nvarchar(max)) IS NULL THEN 'unknown' ELSE LTRIM(RTRIM(LOWER(Channel))) END AS Channel,
        CASE WHEN LOWER(Conversion) IN ('yes','y','1','true') THEN 'Yes' ELSE 'No' END AS Conversion
    FROM dbo.multi_touch_attribution_data
),
UserConversions AS (
    -- first conversion time per user
    SELECT [User_ID], MIN([Timestamp]) AS ConversionTime
    FROM NormalizedTouches
    WHERE Conversion = 'Yes'
    GROUP BY [User_ID]
),
UserJourney AS (
    -- all touches annotated with order
    SELECT nt.[User_ID], nt.[Timestamp], nt.Channel, nt.Conversion,
           ROW_NUMBER() OVER (PARTITION BY nt.[User_ID] ORDER BY nt.[Timestamp] ASC)  AS TouchOrderAsc,
           ROW_NUMBER() OVER (PARTITION BY nt.[User_ID] ORDER BY nt.[Timestamp] DESC) AS TouchOrderDesc
    FROM NormalizedTouches nt
),
TouchesUpToConversion AS (
    -- touches that occurred on or before conversion (only converted users)
    SELECT uj.*, uc.ConversionTime
    FROM UserJourney uj
    JOIN UserConversions uc ON uj.[User_ID] = uc.[User_ID]
    WHERE uj.[Timestamp] <= uc.ConversionTime
),
FirstTouchCredit AS (
    -- 1 credit to first touch channel per converting user
    SELECT Channel, COUNT(DISTINCT [User_ID]) AS FirstTouchCredits
    FROM (SELECT [User_ID], Channel FROM TouchesUpToConversion WHERE TouchOrderAsc = 1) t
    GROUP BY Channel
),
LastTouchCredit AS (
    -- 1 credit to last touch channel per converting user
    SELECT Channel, COUNT(DISTINCT [User_ID]) AS LastTouchCredits
    FROM (SELECT [User_ID], Channel FROM TouchesUpToConversion WHERE TouchOrderDesc = 1) t
    GROUP BY Channel
),
LinearCredit AS (
    -- split 1 conversion evenly across distinct channels seen by each converting user
    SELECT Channel, SUM(Credit) AS LinearCredits
    FROM (
        SELECT [User_ID], Channel, 1.0 / NULLIF(DistinctChannelCount,0) AS Credit
        FROM (
            SELECT [User_ID], Channel,
                   (SELECT COUNT(DISTINCT Channel) FROM TouchesUpToConversion tc2 WHERE tc2.[User_ID] = tc1.[User_ID]) AS DistinctChannelCount
            FROM TouchesUpToConversion tc1
        ) s
        GROUP BY [User_ID], Channel, DistinctChannelCount
    ) x
    GROUP BY Channel
),
TimeDecayCredit AS (
    -- time-decay with geometric factor 0.5 (last touch weight = 1)
    SELECT Channel, SUM(NormalizedWeight) AS TimeDecayCredits
    FROM (
        SELECT [User_ID], Channel,
               POWER(0.5, (TouchOrderDesc - 1)) AS Weight,
               SUM(POWER(0.5, (TouchOrderDesc - 1))) OVER (PARTITION BY [User_ID]) AS TotalWeightPerUser
        FROM TouchesUpToConversion
    ) t
    CROSS APPLY (VALUES (CAST(Weight AS float) / NULLIF(TotalWeightPerUser,0))) AS ca(NormalizedWeight)
    GROUP BY Channel
),
ChannelTotals AS (
    -- union of channels present in the raw data with attribution totals
    SELECT c.Channel,
           ISNULL(f.FirstTouchCredits,0) AS FirstTouchCredits,
           ISNULL(l.LastTouchCredits,0)  AS LastTouchCredits,
           ISNULL(li.LinearCredits,0)    AS LinearCredits,
           ISNULL(td.TimeDecayCredits,0) AS TimeDecayCredits
    FROM (SELECT DISTINCT Channel FROM dbo.multi_touch_attribution_data) c
    LEFT JOIN FirstTouchCredit f ON f.Channel = c.Channel
    LEFT JOIN LastTouchCredit l  ON l.Channel = c.Channel
    LEFT JOIN LinearCredit li    ON li.Channel = c.Channel
    LEFT JOIN TimeDecayCredit td ON td.Channel = c.Channel
)
SELECT a.Channel,
       a.FirstTouchCredits,
       a.LastTouchCredits,
       CAST(a.LinearCredits AS DECIMAL(18,4))    AS LinearCredits,
       CAST(a.TimeDecayCredits AS DECIMAL(18,4)) AS TimeDecayCredits,
       COALESCE(c.TotalCost,0)    AS TotalCost,
       COALESCE(r.TotalRevenue,0) AS TotalRevenue,
       CASE WHEN COALESCE(c.TotalCost,0) = 0 THEN NULL ELSE CAST(r.TotalRevenue / c.TotalCost AS DECIMAL(18,4)) END AS ROI,
       CASE WHEN a.LastTouchCredits = 0 THEN NULL ELSE CAST(c.TotalCost / NULLIF(a.LastTouchCredits,0) AS DECIMAL(18,2)) END AS CostPerLastTouchConversion
FROM ChannelTotals a
LEFT JOIN @ChannelCosts c   ON c.Channel = a.Channel
LEFT JOIN @ChannelRevenue r ON r.Channel = a.Channel
ORDER BY a.FirstTouchCredits DESC;