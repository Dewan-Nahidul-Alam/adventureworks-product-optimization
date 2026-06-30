SELECT sod.SalesOrderDetailID,
    sod.SalesOrderID,
    sod.ProductID,
    cus.TerritoryID,
    soh.OrderDate,
    sod.UnitPrice,
    SUM(sod.OrderQty) as TotalOrderQuantity,
    SUM(sod.UnitPrice * sod.OrderQty) as TotalSales
FROM Sales.SalesOrderDetail sod
    JOIN Sales.SalesOrderHeader soh on sod.SalesOrderID = soh.SalesOrderID
    JOIN Sales.Customer cus on soh.CustomerID = cus.CustomerID
GROUP BY sod.SalesOrderDetailID,
    sod.SalesOrderID,
    sod.ProductID,
    cus.TerritoryID,
    soh.OrderDate,
    sod.UnitPrice;