/* ============================================================================
   AMAZON E-COMMERCE POWER BI CAPSTONE
   ============================================================================ */

use power_bi;
/* ----------------------------------------------------------------------------
   Q14. Top 5 most valuable customers using a composite score:
        Total Revenue (50%) + Order Frequency (30%) + Avg Order Value (20%)
        Each component is min-max normalised (÷ its own maximum) before weighting.
   ---------------------------------------------------------------------------- */
WITH cust_agg AS (
    SELECT
        CustomerID,
        SUM(Sale Price)        AS total_revenue,
        COUNT(orderID)               AS order_frequency,
        AVG(Sale Price)         AS avg_order_value
    FROM Orders
    GROUP BY CustomerID
),
normalised AS (
    SELECT
        CustomerID,
        total_revenue,
        order_frequency,
        avg_order_value,
        total_revenue    / MAX(total_revenue)    OVER () AS revenue_norm,
        order_frequency  / MAX(order_frequency)  OVER () AS frequency_norm,
        avg_order_value  / MAX(avg_order_value)  OVER () AS aov_norm
    FROM cust_agg
)
SELECT 
    CustomerID,
    total_revenue,
    order_frequency,
    avg_order_value,
    ROUND(0.50 * revenue_norm + 0.30 * frequency_norm + 0.20 * aov_norm, 4) AS composite_score
FROM normalised
ORDER BY composite_score DESC
limit 5;

/* ----------------------------------------------------------------------------
   Q15. Month-over-month (MoM) growth rate in total revenue, whole dataset.
   ---------------------------------------------------------------------------- */
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', OrderDate) AS order_month,
        SUM(SalePrice)                  AS revenue
    FROM Orders
    GROUP BY DATE_TRUNC('month', OrderDate)
)
SELECT
    order_month,
    revenue,
    LAG(revenue) OVER (ORDER BY order_month)                       AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
          / LAG(revenue) OVER (ORDER BY order_month), 2)           AS mom_growth_pct
FROM monthly_revenue
ORDER BY order_month;


/* ----------------------------------------------------------------------------
   Q16. Rolling 3-month average revenue for each product category.
   ---------------------------------------------------------------------------- */
WITH monthly_category_revenue AS (
    SELECT
        ProductCategory,
        DATE_TRUNC('month', OrderDate) AS order_month,
        SUM(SalePrice)                  AS revenue
    FROM Orders
    GROUP BY ProductCategory, DATE_TRUNC('month', OrderDate)
)
SELECT
    ProductCategory,
    order_month,
    revenue,
    ROUND(AVG(revenue) OVER (
        PARTITION BY ProductCategory
        ORDER BY order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_3month_avg_revenue
FROM monthly_category_revenue
ORDER BY ProductCategory, order_month;


/* ----------------------------------------------------------------------------
   Q17. Apply a 15% discount to SalePrice for orders placed by customers who
        have made at least 10 orders.
   ---------------------------------------------------------------------------- */
UPDATE Orders
SET SalePrice = SalePrice * 0.85
WHERE CustomerID IN (
    SELECT CustomerID
    FROM Orders
    GROUP BY CustomerID
    HAVING COUNT(*) >= 10
);
-- NOTE: in this dataset every customer has exactly one order, so this UPDATE
-- currently affects 0 rows. It is written to apply correctly on any dataset
-- (or a future data load) where a customer can place 10+ orders. Always
-- wrap production UPDATEs like this in a transaction and verify the affected
-- row count with a SELECT COUNT(*) using the same WHERE clause first.


/* ----------------------------------------------------------------------------
   Q18. Average number of days between consecutive orders, for customers who
        have placed at least 5 orders.
   ---------------------------------------------------------------------------- */
WITH ordered_purchases AS (
    SELECT
        CustomerID,
        OrderDate,
        LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS prev_order_date
    FROM Orders
),
customer_order_counts AS (
    SELECT CustomerID, COUNT(*) AS n_orders
    FROM Orders
    GROUP BY CustomerID
    HAVING COUNT(*) >= 5
)
SELECT
    ROUND(AVG(DATEDIFF(day, o.prev_order_date, o.OrderDate)), 2) AS avg_days_between_orders
FROM ordered_purchases o
INNER JOIN customer_order_counts c ON o.CustomerID = c.CustomerID
WHERE o.prev_order_date IS NOT NULL;
-- NOTE: with every customer having exactly one order in this dataset, no
-- customer qualifies for the >=5-orders filter, so this returns NULL/0 rows
-- here — again, the query is correct for a dataset with genuine repeat buyers.


/* ----------------------------------------------------------------------------
   Q19. Customers whose total revenue is more than 30% higher than the
        average revenue per customer.
   ---------------------------------------------------------------------------- */
WITH customer_revenue AS (
    SELECT CustomerID, SUM(SalePrice) AS total_revenue
    FROM Orders
    GROUP BY CustomerID
),
avg_revenue AS (
    SELECT AVG(total_revenue) AS avg_customer_revenue FROM customer_revenue
)
SELECT
    cr.CustomerID,
    cr.total_revenue,
    ar.avg_customer_revenue,
    ROUND(100.0 * (cr.total_revenue - ar.avg_customer_revenue) / ar.avg_customer_revenue, 2) AS pct_above_avg
FROM customer_revenue cr
CROSS JOIN avg_revenue ar
WHERE cr.total_revenue > 1.30 * ar.avg_customer_revenue
ORDER BY cr.total_revenue DESC;
-- RESULT on the actual dataset: 21,023 customers (out of 113,000) qualify.


/* ----------------------------------------------------------------------------
   Q20. Top 3 product categories with the highest YoY sales increase versus
        the previous year (using the two most recent full years: 2020 vs 2019).
   ---------------------------------------------------------------------------- */
WITH category_year_revenue AS (
    SELECT
        ProductCategory,
        EXTRACT(YEAR FROM OrderDate) AS order_year,
        SUM(SalePrice)                AS revenue
    FROM Orders
    WHERE ProductCategory IS NOT NULL
    GROUP BY ProductCategory, EXTRACT(YEAR FROM OrderDate)
)
SELECT TOP 3
    ProductCategory,
    MAX(CASE WHEN order_year = 2020 THEN revenue END) AS revenue_2020,
    MAX(CASE WHEN order_year = 2019 THEN revenue END) AS revenue_2019,
    ROUND(100.0 * (
        MAX(CASE WHEN order_year = 2020 THEN revenue END) -
        MAX(CASE WHEN order_year = 2019 THEN revenue END)
    ) / MAX(CASE WHEN order_year = 2019 THEN revenue END), 2) AS yoy_growth_pct
FROM category_year_revenue
GROUP BY ProductCategory
ORDER BY yoy_growth_pct DESC;
-- RESULT: 1) Electronics +47.29%  2) Health and beauty +42.44%  3) Fashion +41.93%


/* ----------------------------------------------------------------------------
   SUPPORTING QUERIES referenced in the Word report (objective questions)
   ---------------------------------------------------------------------------- */

-- Q1: total attributes (columns) in the Customers table
SELECT COUNT(*) AS total_attributes
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Customers';                     -- = 3 (CustomerID, CustomerAge, CustomerGender)

-- Q2: pull a customer's age into the Orders grain via a join on CustomerID
SELECT o.OrderID, o.CustomerID, c.CustomerAge, c.CustomerGender
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID;

-- Q4: total revenue generated by all sales
SELECT ROUND(SUM(SalePrice), 2) AS total_revenue FROM Orders;      -- = GHS 107,239,297.20

-- Q5: unique customers per year
SELECT EXTRACT(YEAR FROM OrderDate) AS order_year, COUNT(DISTINCT CustomerID) AS unique_customers
FROM Orders GROUP BY EXTRACT(YEAR FROM OrderDate) ORDER BY 1;

-- Q6: unique products
SELECT COUNT(DISTINCT Product) AS unique_products FROM Orders;     -- = 44

-- Q7: average delivery time, delivered orders only
SELECT ROUND(AVG(DATEDIFF(day, OrderDate, DeliveryDate)), 2) AS avg_delivery_days
FROM Orders WHERE Status = 'Delivered';                             -- = 9.41 days

-- Q8: most popular categories/subcategories by revenue
SELECT ProductCategory, SUM(SalePrice) AS revenue, COUNT(*) AS orders
FROM Orders GROUP BY ProductCategory ORDER BY revenue DESC;
