WITH ProductPerformance AS (
    -- Basic product performance analysis
    SELECT p.ProductID,
        p.ProductName,
        p.ProductCategoryName,
        p.StandardCost,
        SUM(f.TotalSales) AS TotalRevenue
    FROM ProductDevelopment.FactSales f
        JOIN ProductDevelopment.DimProduct p ON f.ProductID = p.ProductID
    GROUP BY p.ProductID,
        p.ProductName,
        p.ProductCategoryName,
        p.StandardCost
),
AvgMetrics AS (
    -- Calculate global average metrics
    SELECT AVG(StandardCost) AS AvgCost,
        AVG(TotalRevenue) AS AvgRevenue
    FROM ProductPerformance
),
HighCostLowSales AS (
    -- Identify products with high cost and low sales
    SELECT pp.*
    FROM ProductPerformance pp
        CROSS JOIN AvgMetrics am
    WHERE pp.StandardCost > am.AvgCost
        AND pp.TotalRevenue < am.AvgRevenue
),
-- Get quarterly sales data for each product, sorted by time
ProductQuarterlySales AS (
    SELECT p.ProductID,
        p.ProductName,
        p.ProductCategoryName,
        d.Year AS SalesYear,
        d.Quarter AS SalesQuarter,
        SUM(f.TotalOrderQuantity) AS QuarterlyUnits,
        SUM(f.TotalSales) AS QuarterlyRevenue,
        COUNT(DISTINCT f.SalesOrderID) AS QuarterlyOrders,
        -- Calculate quarter rank for each product (1 = most recent quarter for that product)
        ROW_NUMBER() OVER (
            PARTITION BY p.ProductID
            ORDER BY d.Year DESC,
                d.Quarter DESC
        ) AS ProductQuarterRank
    FROM ProductDevelopment.FactSales f
        JOIN ProductDevelopment.DimDate d ON f.OrderDate = d.DateKey
        JOIN ProductDevelopment.DimProduct p ON f.ProductID = p.ProductID
    GROUP BY p.ProductID,
        p.ProductName,
        p.ProductCategoryName,
        d.Year,
        d.Quarter
),
-- Add quarter-over-quarter growth calculation based on each product's own timeline
ProductTrends AS (
    SELECT qs.*,
        LAG(qs.QuarterlyRevenue) OVER (
            PARTITION BY qs.ProductID
            ORDER BY qs.SalesYear,
                qs.SalesQuarter
        ) AS PrevQuarterRevenue,
        LAG(qs.QuarterlyUnits) OVER (
            PARTITION BY qs.ProductID
            ORDER BY qs.SalesYear,
                qs.SalesQuarter
        ) AS PrevQuarterUnits,
        -- Calculate QoQ growth percentage
        CASE
            WHEN LAG(qs.QuarterlyRevenue) OVER (
                PARTITION BY qs.ProductID
                ORDER BY qs.SalesYear,
                    qs.SalesQuarter
            ) > 0 THEN (
                qs.QuarterlyRevenue - LAG(qs.QuarterlyRevenue) OVER (
                    PARTITION BY qs.ProductID
                    ORDER BY qs.SalesYear,
                        qs.SalesQuarter
                )
            ) / LAG(qs.QuarterlyRevenue) OVER (
                PARTITION BY qs.ProductID
                ORDER BY qs.SalesYear,
                    qs.SalesQuarter
            ) * 100
            ELSE NULL
        END AS RevenueQoQGrowth
    FROM ProductQuarterlySales qs
),
-- Aggregate recent performance metrics for each product
ProductAggregated AS (
    SELECT t.ProductID,
        t.ProductName,
        t.ProductCategoryName,
        -- Most recent quarter data (ProductQuarterRank = 1)
        MAX(
            CASE
                WHEN t.ProductQuarterRank = 1 THEN CONCAT('Q', t.SalesQuarter, '-', t.SalesYear)
            END
        ) AS LatestQuarter,
        MAX(
            CASE
                WHEN t.ProductQuarterRank = 1 THEN t.QuarterlyRevenue
            END
        ) AS LatestQuarterRevenue,
        MAX(
            CASE
                WHEN t.ProductQuarterRank = 1 THEN t.QuarterlyUnits
            END
        ) AS LatestQuarterUnits,
        -- Previous quarter data (ProductQuarterRank = 2)
        MAX(
            CASE
                WHEN t.ProductQuarterRank = 2 THEN t.QuarterlyRevenue
            END
        ) AS PreviousQuarterRevenue,
        MAX(
            CASE
                WHEN t.ProductQuarterRank = 2 THEN t.QuarterlyUnits
            END
        ) AS PreviousQuarterUnits,
        -- Average growth rate of the last two quarters
        AVG(
            CASE
                WHEN t.ProductQuarterRank <= 2
                AND t.RevenueQoQGrowth IS NOT NULL THEN t.RevenueQoQGrowth
            END
        ) AS AvgRecentQoQGrowth,
        -- Whether the product has sales in the last two quarters
        MAX(
            CASE
                WHEN t.ProductQuarterRank <= 2 THEN 1
                ELSE 0
            END
        ) AS HasRecentSales,
        -- Total revenue and units for the last four quarters
        SUM(
            CASE
                WHEN t.ProductQuarterRank <= 4 THEN t.QuarterlyRevenue
                ELSE 0
            END
        ) AS Last4QuartersRevenue,
        SUM(
            CASE
                WHEN t.ProductQuarterRank <= 4 THEN t.QuarterlyUnits
                ELSE 0
            END
        ) AS Last4QuartersUnits,
        -- Total number of quarters with sales
        COUNT(*) AS TotalQuartersWithSales,
        -- Average quarterly revenue
        AVG(t.QuarterlyRevenue) AS AvgQuarterlyRevenue
    FROM ProductTrends t
    WHERE t.ProductID IN (
            SELECT ProductID
            FROM HighCostLowSales
        )
    GROUP BY t.ProductID,
        t.ProductName,
        t.ProductCategoryName
),
-- Calculate global average quarterly revenue for comparison
GlobalAvgQuarterlyRevenue AS (
    SELECT AVG(QuarterlyRevenue) AS GlobalAvgQuarterlyRevenue
    FROM ProductQuarterlySales
) -- Final output
SELECT pa.ProductID,
    pa.ProductName,
    pa.ProductCategoryName AS CategoryName,
    -- Quarter information
    pa.LatestQuarter,
    CAST(
        ISNULL(pa.LatestQuarterRevenue, 0) AS DECIMAL(10, 2)
    ) AS LatestQuarterRevenue,
    ISNULL(pa.LatestQuarterUnits, 0) AS LatestQuarterUnits,
    CAST(
        ISNULL(pa.PreviousQuarterRevenue, 0) AS DECIMAL(10, 2)
    ) AS PreviousQuarterRevenue,
    ISNULL(pa.PreviousQuarterUnits, 0) AS PreviousQuarterUnits,
    -- Recent total sales
    CAST(
        ISNULL(pa.Last4QuartersRevenue, 0) AS DECIMAL(10, 2)
    ) AS Last4QuartersRevenue,
    ISNULL(pa.Last4QuartersUnits, 0) AS Last4QuartersUnits,
    -- Growth metrics
    CAST(
        ISNULL(pa.AvgRecentQoQGrowth, 0) AS DECIMAL(10, 2)
    ) AS QoQ_Growth_Percent,
    -- Trend classification
    CASE
        WHEN pa.HasRecentSales = 0 THEN 'No Recent Sales'
        WHEN ISNULL(pa.AvgRecentQoQGrowth, 0) > 10 THEN 'Growing'
        WHEN ISNULL(pa.AvgRecentQoQGrowth, 0) < -10 THEN 'Declining'
        ELSE 'Stable'
    END AS RecentTrend,
    -- Short-term momentum (comparing the last two quarters)
    CASE
        WHEN pa.LatestQuarterRevenue > ISNULL(pa.PreviousQuarterRevenue, 0) * 1.2 THEN 'Strong Upward'
        WHEN pa.LatestQuarterRevenue > ISNULL(pa.PreviousQuarterRevenue, 0) * 1.05 THEN 'Upward'
        WHEN pa.LatestQuarterRevenue < ISNULL(pa.PreviousQuarterRevenue, 0) * 0.8 THEN 'Strong Downward'
        WHEN pa.LatestQuarterRevenue < ISNULL(pa.PreviousQuarterRevenue, 0) * 0.95 THEN 'Downward'
        ELSE 'Flat'
    END AS ShortTermMomentum,
    -- Product average quarterly revenue
    CAST(
        ISNULL(pa.AvgQuarterlyRevenue, 0) AS DECIMAL(10, 2)
    ) AS AvgQuarterlyRevenue,
    pa.TotalQuartersWithSales,
    -- Comprehensive recommendation
    CASE
        -- No recent sales
        WHEN pa.HasRecentSales = 0 THEN 'Consider Discontinuation - No Recent Sales' -- High cost, low sales, and declining
        WHEN pa.AvgRecentQoQGrowth < -10
        AND pa.LatestQuarterRevenue < ga.GlobalAvgQuarterlyRevenue * 0.5
        AND pa.LatestQuarterRevenue < pa.AvgQuarterlyRevenue * 0.5 THEN 'Strongly Recommend Discontinuation' -- Declining but still above average
        WHEN pa.AvgRecentQoQGrowth < -10
        AND pa.LatestQuarterRevenue > ga.GlobalAvgQuarterlyRevenue * 0.5 THEN 'Monitor Closely - Declining but Still Selling' -- Growing from a low base
        WHEN pa.AvgRecentQoQGrowth > 10
        AND pa.LatestQuarterRevenue < ga.GlobalAvgQuarterlyRevenue * 0.3 THEN 'Consider Marketing Boost - Growing from Low Base' -- Growing and performing well
        WHEN pa.AvgRecentQoQGrowth > 10
        AND pa.LatestQuarterRevenue > pa.AvgQuarterlyRevenue THEN 'Retain - Showing Strong Recent Growth' -- Stable but poor performance
        WHEN pa.AvgRecentQoQGrowth BETWEEN -10 AND 10
        AND pa.LatestQuarterRevenue < ga.GlobalAvgQuarterlyRevenue * 0.3 THEN 'Consider Cost Reduction or Redesign' -- New product
        WHEN pa.TotalQuartersWithSales < 4 THEN 'New Product - Needs More Data'
        ELSE 'Further Analysis Required'
    END AS Recommendation,
    -- Priority level
    CASE
        WHEN pa.HasRecentSales = 0 THEN 'High'
        WHEN pa.AvgRecentQoQGrowth < -10
        AND pa.LatestQuarterRevenue < ga.GlobalAvgQuarterlyRevenue * 0.3 THEN 'High'
        WHEN pa.AvgRecentQoQGrowth < -10 THEN 'Medium'
        WHEN pa.AvgRecentQoQGrowth > 10 THEN 'Low'
        ELSE 'Medium'
    END AS PriorityLevel
FROM ProductAggregated pa
    CROSS JOIN GlobalAvgQuarterlyRevenue ga
WHERE pa.HasRecentSales = 1 -- only show products with recent sales
    OR pa.TotalQuartersWithSales > 0
ORDER BY pa.ProductCategoryName,
    CASE
        WHEN pa.HasRecentSales = 0 THEN 1
        WHEN ISNULL(pa.AvgRecentQoQGrowth, 0) < -10 THEN 2
        WHEN ISNULL(pa.AvgRecentQoQGrowth, 0) BETWEEN -10 AND 10 THEN 3
        ELSE 4
    END;
