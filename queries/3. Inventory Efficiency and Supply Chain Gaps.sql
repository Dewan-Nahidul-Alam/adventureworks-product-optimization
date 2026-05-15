-- Total Sales Volume and Inventory per product
WITH ProductSalesPerformance AS (
    SELECT p.ProductID,
        p.ProductName,
        p.ProductCategoryName,
        p.InventoryQuantity,
        SUM(f.TotalOrderQuantity) AS TotalVolumeSold
    FROM ProductDevelopment.FactSales f
        JOIN ProductDevelopment.DimProduct p ON f.ProductID = p.ProductID
    GROUP BY p.ProductID,
        p.ProductName,
        p.ProductCategoryName,
        p.InventoryQuantity
),
-- Global averages for the entire catalog
GlobalAverages AS (
    SELECT AVG(CAST(TotalVolumeSold AS FLOAT)) AS AvgGlobalVolume,
        AVG(CAST(InventoryQuantity AS FLOAT)) AS AvgGlobalInventory
    FROM ProductSalesPerformance
) -- Products that are “High Volume” but “Low Inventory”
SELECT psp.ProductName,
    psp.ProductCategoryName,
    psp.TotalVolumeSold,
    ROUND(ga.AvgGlobalVolume, 2) AS BenchmarkAvgVolume,
    psp.InventoryQuantity,
    ROUND(ga.AvgGlobalInventory, 2) AS BenchmarkAvgInventory,
    CASE
        WHEN psp.TotalVolumeSold > ga.AvgGlobalVolume
        AND psp.InventoryQuantity < ga.AvgGlobalInventory THEN 'Efficiency Star'
        WHEN psp.TotalVolumeSold > ga.AvgGlobalVolume
        AND psp.InventoryQuantity > ga.AvgGlobalInventory THEN 'Mass Market'
        WHEN psp.TotalVolumeSold < ga.AvgGlobalVolume
        AND psp.InventoryQuantity < ga.AvgGlobalInventory THEN 'Niche'
        WHEN psp.TotalVolumeSold < ga.AvgGlobalVolume
        AND psp.InventoryQuantity > ga.AvgGlobalInventory THEN 'Overstock'
    END as ProductClassification
FROM ProductSalesPerformance psp,
    GlobalAverages ga
WHERE psp.InventoryQuantity IS NOT NULL
ORDER BY psp.TotalVolumeSold DESC;
