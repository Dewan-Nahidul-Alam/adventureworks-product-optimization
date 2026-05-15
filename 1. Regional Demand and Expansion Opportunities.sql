-- Aggregate sales by territory and product category
WITH BaseSales AS (
    SELECT t.CountryRegionCode,
        t.TerritoryName,
        p.ProductCategoryName,
        SUM(f.TotalOrderQuantity) AS TotalSalesQuantity -- Total quantity sold in each category per territory
    FROM ProductDevelopment.FactSales AS f
        JOIN ProductDevelopment.DimProduct AS p ON f.ProductID = p.ProductID -- Join product details
        JOIN ProductDevelopment.DimTerritory AS t ON f.TerritoryID = t.TerritoryID -- Join territory details
    GROUP BY t.CountryRegionCode,
        t.TerritoryName,
        p.ProductCategoryName
),
-- Convert product categories into columns
PivotTable AS (
    SELECT CountryRegionCode,
        TerritoryName,
        ISNULL([Accessories], 0) AS Accessories,
        ISNULL([Bikes], 0) AS Bikes,
        ISNULL([Clothing], 0) AS Clothing,
        ISNULL([Components], 0) AS Components
    FROM BaseSales PIVOT (
            SUM(TotalSalesQuantity) -- Pivot summed quantities
            FOR ProductCategoryName IN (
                [Accessories],
                [Bikes],
                [Clothing],
                [Components]
            ) -- Create one column per category
        ) AS p
) -- Calculate territory totals, country totals, and market share
SELECT CountryRegionCode,
    TerritoryName,
    Accessories,
    Bikes,
    Clothing,
    Components,
    Accessories + Bikes + Clothing + Components AS TerritoryTotalQuantity,
    -- Total quantity sold in each territory
    SUM(Accessories + Bikes + Clothing + Components) OVER (PARTITION BY CountryRegionCode) AS CountryRegionTotalQuantity,
    -- Total quantity sold across all territories in the same country
    CONCAT(
        CAST(
            ROUND(
                (Accessories + Bikes + Clothing + Components) * 100.0 / SUM(Accessories + Bikes + Clothing + Components) OVER (PARTITION BY CountryRegionCode),2
            ) AS DECIMAL(10, 2)),'%'
    ) AS TerritoryShareWithinCountry -- Territory's percentage contribution within its country
FROM PivotTable -- Rank territories by sales volume within each country
ORDER BY CountryRegionCode,
    TerritoryTotalQuantity DESC;
