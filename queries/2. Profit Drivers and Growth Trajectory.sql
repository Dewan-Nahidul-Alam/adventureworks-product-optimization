WITH MaxDateAnchor AS (
    -- STEP 1: Identify the absolute latest date for TTM anchoring
    SELECT MAX(dd.[Date]) AS LatestDate
    FROM ProductDevelopment.FactSales fs
        JOIN ProductDevelopment.DimDate dd ON fs.OrderDate = dd.DateKey
),
TTMData AS (
    -- STEP 2: Aggregate margins for current vs. prior 12-month windows
    SELECT dp.ProductSubcategoryName,
        SUM(
            CASE
                WHEN dd.[Date] > DATEADD(MONTH, -12, mda.LatestDate)
                AND dd.[Date] <= mda.LatestDate THEN (fs.UnitPrice - dp.StandardCost) * fs.TotalOrderQuantity
                ELSE 0
            END
        ) AS CurrentTTMMargin,
        SUM(
            CASE
                WHEN dd.[Date] > DATEADD(MONTH, -24, mda.LatestDate)
                AND dd.[Date] <= DATEADD(MONTH, -12, mda.LatestDate) THEN (fs.UnitPrice - dp.StandardCost) * fs.TotalOrderQuantity
                ELSE 0
            END
        ) AS PriorTTMMargin
    FROM ProductDevelopment.FactSales fs
        JOIN ProductDevelopment.DimProduct dp ON fs.ProductID = dp.ProductID
        JOIN ProductDevelopment.DimDate dd ON fs.OrderDate = dd.DateKey
        CROSS JOIN MaxDateAnchor mda
    GROUP BY dp.ProductSubcategoryName
) -- STEP 3: Calculate the Growth Rates for the Top 10 Profit Drivers
SELECT TOP 10 ProductSubcategoryName,
    CurrentTTMMargin,
    PriorTTMMargin,
    CASE
        WHEN PriorTTMMargin = 0 THEN NULL
        WHEN PriorTTMMargin < 0
        AND CurrentTTMMargin > 0 THEN (CurrentTTMMargin - PriorTTMMargin) / ABS(PriorTTMMargin)
        ELSE (CurrentTTMMargin - PriorTTMMargin) / NULLIF(PriorTTMMargin, 0)
    END AS MarginGrowthRate
FROM TTMData
ORDER BY CurrentTTMMargin DESC;