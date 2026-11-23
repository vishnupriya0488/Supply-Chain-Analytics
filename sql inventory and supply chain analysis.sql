create database supply_chain;

Use supply_chain;

select count(*) from fact_order;

select count(*) from fact_inventory;

select count(*) from dim_customer;


USE supply_chain;

-- KPI 1: Total Sales (MTD, QTD, YTD)
SELECT
    d.as_of_date,
    ROUND(SUM(CASE WHEN o.Order_Date >= DATE_FORMAT(d.as_of_date, '%Y-%m-01')
                   AND  o.Order_Date <= d.as_of_date THEN o.Revenue ELSE 0 END), 2) AS mtd_sales,
    ROUND(SUM(CASE WHEN o.Order_Date >= MAKEDATE(YEAR(d.as_of_date), 1) + INTERVAL (QUARTER(d.as_of_date) - 1) QUARTER
                   AND  o.Order_Date <= d.as_of_date THEN o.Revenue ELSE 0 END), 2) AS qtd_sales,
    ROUND(SUM(CASE WHEN o.Order_Date >= MAKEDATE(YEAR(d.as_of_date), 1)
                   AND  o.Order_Date <= d.as_of_date THEN o.Revenue ELSE 0 END), 2) AS ytd_sales
FROM fact_order o
CROSS JOIN (SELECT MAX(Order_Date) AS as_of_date FROM fact_order) d
GROUP BY d.as_of_date;

describe dim_product;

USE supply_chain;

DROP PROCEDURE IF EXISTS fix_first_col;
DELIMITER $$
CREATE PROCEDURE fix_first_col(IN t VARCHAR(64), IN newname VARCHAR(64))
BEGIN
    SET @old = (SELECT COLUMN_NAME FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = 'supply_chain' AND TABLE_NAME = t
                  AND ORDINAL_POSITION = 1);
    SET @sql = CONCAT('ALTER TABLE `', t, '` CHANGE `', @old, '` `', newname, '` TEXT');
    PREPARE s FROM @sql;
    EXECUTE s;
    DEALLOCATE PREPARE s;
END$$
DELIMITER ;

CALL fix_first_col('dim_product',    'Product_ID');
CALL fix_first_col('dim_customer',   'Customer_ID');
CALL fix_first_col('dim_warehouse',  'Warehouse_ID');
CALL fix_first_col('dim_supplier',   'Supplier_ID');
CALL fix_first_col('fact_order',     'Order_ID');
CALL fix_first_col('fact_inventory', 'Product_ID');

-- KPI 2: Product Wise Sales
SELECT
    p.Category,
    p.Product_ID,
    p.Product_Name,
    SUM(o.Order_Quantity)    AS units_sold,
    ROUND(SUM(o.Revenue), 2) AS total_sales
FROM fact_order o
JOIN dim_product p ON p.Product_ID = o.Product_ID
GROUP BY p.Category, p.Product_ID, p.Product_Name
ORDER BY total_sales DESC;


-- KPI 3: Sales Growth (Month-over-Month and Year-over-Year %)
WITH monthly AS (
    SELECT
        DATE_FORMAT(Order_Date, '%Y-%m') AS year_month_key,
        SUM(Revenue) AS sales
    FROM fact_order
    GROUP BY DATE_FORMAT(Order_Date, '%Y-%m')
)
SELECT
    year_month_key,
    ROUND(sales, 2) AS sales,
    ROUND((sales - LAG(sales, 1)  OVER (ORDER BY year_month_key))
          / NULLIF(LAG(sales, 1)  OVER (ORDER BY year_month_key), 0) * 100, 2) AS mom_growth_pct,
    ROUND((sales - LAG(sales, 12) OVER (ORDER BY year_month_key))
          / NULLIF(LAG(sales, 12) OVER (ORDER BY year_month_key), 0) * 100, 2) AS yoy_growth_pct
FROM monthly
ORDER BY year_month_key;


-- KPI 4: Daily Sales Trend
SELECT
    Order_Date,
    COUNT(*)               AS order_lines,
    SUM(Order_Quantity)    AS units_sold,
    ROUND(SUM(Revenue), 2) AS daily_sales
FROM fact_order
GROUP BY Order_Date
ORDER BY Order_Date;


-- KPI 5: State Wise Sales (customer country, as there is no state column)
SELECT
    c.Customer_Country AS state_or_country,
    ROUND(SUM(o.Revenue), 2) AS total_sales,
    COUNT(*) AS order_lines
FROM fact_order o
JOIN dim_customer c ON c.Customer_ID = o.Customer_ID
GROUP BY c.Customer_Country
ORDER BY total_sales DESC;


-- KPI 6: Top 5 Store Wise Sales (store = warehouse)
SELECT
    w.Warehouse_ID   AS store_id,
    w.Warehouse_City AS store_city,
    ROUND(SUM(o.Revenue), 2) AS total_sales
FROM fact_order o
JOIN dim_warehouse w ON w.Warehouse_ID = o.Warehouse_ID
GROUP BY w.Warehouse_ID, w.Warehouse_City
ORDER BY total_sales DESC
LIMIT 5;


-- KPI 7: Region Wise Sales
SELECT
    c.Customer_Region AS region,
    ROUND(SUM(o.Revenue), 2) AS total_sales,
    COUNT(*) AS order_lines
FROM fact_order o
JOIN dim_customer c ON c.Customer_ID = o.Customer_ID
GROUP BY c.Customer_Region
ORDER BY total_sales DESC;


-- KPI 8: Total Inventory (units on hand, latest snapshot)
SELECT
    Snapshot_Date,
    SUM(Stock_On_Hand) AS total_inventory_units
FROM fact_inventory
WHERE Snapshot_Date = (SELECT MAX(Snapshot_Date) FROM fact_inventory)
GROUP BY Snapshot_Date;


-- KPI 9: Inventory Value (stock on hand x unit cost, latest snapshot)
SELECT
    i.Snapshot_Date,
    ROUND(SUM(i.Stock_On_Hand * p.Unit_Cost), 2) AS inventory_value_at_cost
FROM fact_inventory i
JOIN dim_product p ON p.Product_ID = i.Product_ID
WHERE i.Snapshot_Date = (SELECT MAX(Snapshot_Date) FROM fact_inventory)
GROUP BY i.Snapshot_Date;


-- KPI 10: Overstock, Out-of-stock, Under-stock (latest snapshot)
SELECT
    stock_status,
    COUNT(*)           AS product_warehouse_combos,
    SUM(Stock_On_Hand) AS units_on_hand
FROM (
    SELECT
        Stock_On_Hand,
        CASE
            WHEN Stock_On_Hand <= 0                 THEN 'Out-of-stock'
            WHEN Stock_On_Hand <  Reorder_Level     THEN 'Under-stock'
            WHEN Stock_On_Hand >  3 * Reorder_Level THEN 'Overstock'
            ELSE 'In-stock'
        END AS stock_status
    FROM fact_inventory
    WHERE Snapshot_Date = (SELECT MAX(Snapshot_Date) FROM fact_inventory)
) s
GROUP BY stock_status
ORDER BY units_on_hand DESC;


-- KPI 11: Purchase Method Wise Sales (Ship_Mode used, no payment column)
SELECT
    Ship_Mode AS purchase_method,
    COUNT(*) AS order_lines,
    ROUND(SUM(Revenue), 2) AS total_sales,
    ROUND(SUM(Revenue) / (SELECT SUM(Revenue) FROM fact_order) * 100, 2) AS pct_of_total_sales
FROM fact_order
GROUP BY Ship_Mode
ORDER BY total_sales DESC;

-- KPI 1.1: Total Orders, Total Sales Revenue, Average Order Value
SELECT
    COUNT(Order_ID)                          AS total_orders,
    ROUND(SUM(Revenue), 2)                   AS total_sales_revenue,
    ROUND(SUM(Revenue) / COUNT(Order_ID), 2) AS avg_order_value
FROM fact_order;

-- KPI 1.2: Orders by Region / Country / City
SELECT c.Customer_Region, c.Customer_Country, c.Customer_City,
       COUNT(o.Order_ID) AS total_orders
FROM fact_order o
JOIN dim_customer c ON c.Customer_ID = o.Customer_ID
GROUP BY c.Customer_Region, c.Customer_Country, c.Customer_City
ORDER BY total_orders DESC;

-- KPI 2.1: Stock on Hand (latest snapshot)
SELECT Snapshot_Date, SUM(Stock_On_Hand) AS stock_on_hand
FROM fact_inventory
WHERE Snapshot_Date = (SELECT MAX(Snapshot_Date) FROM fact_inventory)
GROUP BY Snapshot_Date;

-- KPI 2.2: Reorder Status (% below reorder level, latest snapshot)
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN Stock_On_Hand < Reorder_Level THEN 1 ELSE 0 END) AS rows_below_reorder_level,
       ROUND(100 * SUM(CASE WHEN Stock_On_Hand < Reorder_Level THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_below_reorder_level
FROM fact_inventory
WHERE Snapshot_Date = (SELECT MAX(Snapshot_Date) FROM fact_inventory);

-- KPI 2.3: Average Lead Time (order date to delivery date)
SELECT ROUND(AVG(DATEDIFF(Actual_Delivery_Date, Order_Date)), 2) AS avg_lead_time_days
FROM fact_order;

-- KPI 2.4: Inventory Turnover Ratio (2024 COGS / average inventory value)
SELECT ROUND(
    (SELECT SUM(COGS) FROM fact_order WHERE YEAR(Order_Date) = 2024)
    /
    (SELECT SUM(i.Stock_On_Hand * p.Unit_Cost) / COUNT(DISTINCT i.Snapshot_Date)
       FROM fact_inventory i
       JOIN dim_product p ON p.Product_ID = i.Product_ID)
, 2) AS inventory_turnover_ratio;

-- KPI 3.1 to 3.4: Procurement, Transportation, Total Supply Chain Cost, Cost per Unit
SELECT ROUND(SUM(COGS), 2)                                        AS procurement_cost,
       ROUND(SUM(Shipping_Cost), 2)                               AS transportation_cost,
       ROUND(SUM(COGS + Shipping_Cost), 2)                        AS total_supply_chain_cost,
       ROUND(SUM(COGS + Shipping_Cost) / SUM(Order_Quantity), 2)  AS cost_per_unit
FROM fact_order;

-- KPI 4.1: On-Time Delivery %
SELECT ROUND(100 * SUM(Delivery_Status = 'On-Time') / COUNT(*), 2) AS on_time_delivery_pct
FROM fact_order;

-- KPI 4.2: Average Delay (days)
SELECT ROUND(AVG(Delay_Days), 2) AS avg_delay_days
FROM fact_order;

-- KPI 4.3: Orders by Ship Mode
SELECT Ship_Mode, COUNT(*) AS total_orders,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fact_order), 2) AS pct_of_orders
FROM fact_order
GROUP BY Ship_Mode
ORDER BY total_orders DESC;

-- KPI 4.4: Transport Mode Utilization (orders per ship mode and carrier)
SELECT Ship_Mode, Carrier, COUNT(*) AS total_orders
FROM fact_order
GROUP BY Ship_Mode, Carrier
ORDER BY Ship_Mode, total_orders DESC;

-- KPI 5.1: Forecast Accuracy (stand-in: previous month's demand = forecast)
WITH monthly AS (
    SELECT DATE_FORMAT(Order_Date, '%Y-%m') AS ym, SUM(Order_Quantity) AS demand
    FROM fact_order
    GROUP BY DATE_FORMAT(Order_Date, '%Y-%m')
),
f AS (
    SELECT ym, demand, LAG(demand) OVER (ORDER BY ym) AS forecast_demand
    FROM monthly
)
SELECT ym, forecast_demand, demand AS actual_demand,
       ROUND((1 - ABS(forecast_demand - demand) / forecast_demand) * 100, 2) AS forecast_accuracy_pct
FROM f
WHERE forecast_demand IS NOT NULL
ORDER BY ym;

-- KPI 5.2: Fill Rate
SELECT ROUND(AVG(Fill_Rate_Pct), 2) AS avg_fill_rate_pct,
       ROUND(100 * SUM(Shipped_Quantity) / SUM(Order_Quantity), 2) AS fulfilled_qty_pct
FROM fact_order;

-- KPI 5.3: Backorder Rate (orders shipped short of quantity ordered)
SELECT ROUND(100 * SUM(Shipped_Quantity < Order_Quantity) / COUNT(*), 2) AS backorder_rate_pct
FROM fact_order;

-- KPI 5.4: Demand vs Actual Sales Trend (monthly)
SELECT DATE_FORMAT(Order_Date, '%Y-%m') AS year_month_key,
       SUM(Order_Quantity)   AS demand_units,
       SUM(Shipped_Quantity) AS actual_units_shipped
FROM fact_order
GROUP BY DATE_FORMAT(Order_Date, '%Y-%m')
ORDER BY year_month_key;