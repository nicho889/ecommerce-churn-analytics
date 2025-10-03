/* ================================================================
   EXPLORATION.SQL — E-Commerce Churn Dataset
   Source: (CSV file from Kaggle, etc.)
   Goal: Exploratory SQL analysis to understand churn patterns,
         build retention insights, and prepare views for Tableau.
   Environment: PostgreSQL
   ================================================================= */

/* Create table and reading the csv file */
DROP TABLE IF EXISTS ecom_churn;
CREATE TABLE ecom_churn (
    CustomerID INT PRIMARY KEY,
    Churn INT,
    Tenure INT,
    PreferredLoginDevice VARCHAR,
    CityTier INT,
    WarehouseToHome INT,
    PreferredPaymentMode VARCHAR,
    Gender VARCHAR,
    HourSpendOnApp INT,
    NumberOfDeviceRegistered INT,
    PreferedOrderCat VARCHAR,
    SatisfactionScore INT,
    MaritalStatus VARCHAR,
    NumberOfAddress INT,
    Complain INT,
    OrderAmountHikeFromlastYear INT,
    CouponUsed INT,
    OrderCount INT,
    DaySinceLastOrder INT,
    CashbackAmount INT
);

COPY ecom_churn
FROM 'C:/ecommerce_data/E-Commerce Churn Data.csv'
DELIMITER ','
CSV HEADER;

/* 1) Sanity checks and data quality */
-- Row count
SELECT COUNT(*) AS rows
FROM ecom_churn;

-- Check for duplicate CustomerIDs
SELECT COUNT(*) AS duplicate_customers
FROM (
    SELECT CustomerID
    FROM ecom_churn
    GROUP BY CustomerID
    HAVING COUNT(*)>1
);

-- Nulls overview (important columns)
SELECT
    SUM(CASE WHEN Churn IS NULL THEN 1 ELSE 0 END) AS null_churn,
    SUM(CASE WHEN PreferredLoginDevice IS NULL THEN 1 ELSE 0 END) AS null_device,
    SUM(CASE WHEN PreferedOrderCat IS NULL THEN 1 ELSE 0 END) AS null_order_cat,
    SUM(CASE WHEN PreferredPaymentMode IS NULL THEN 1 ELSE 0 END) AS null_payment
FROM ecom_churn;

/* 2) Core KPIs */
-- Overall churn rate (percentage of customers with churn=1)
SELECT ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn;

-- Check ranges of key numeric variables (tenure, cashback)
SELECT MIN(Tenure) AS min_tenure,
    MAX(Tenure) AS max_tenure
FROM ecom_churn;

SELECT MIN(CashbackAmount) AS min_cashback,
    MAX(CashbackAmount) AS max_cashback
FROM ecom_churn;

/* 3) Segment cuts - where is churn highest? */
-- By login device
-- Helps us see if churn varies a lot between customers who used phone/computer/mobile phone
SELECT PreferredLoginDevice,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY PreferredLoginDevice
ORDER BY churn_rate DESC, customers DESC;

-- By payment mode
SELECT PreferredPaymentMode,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY PreferredPaymentMode
ORDER BY churn_rate DESC, customers DESC;

SELECT
    CASE
        WHEN PreferredPaymentMode IN ('COD', 'Cash on Delivery') THEN 'Cash on Delivery'
        WHEN PreferredPaymentMode IN ('CC', 'Credit Card') THEN 'Credit Card'
        WHEN PreferredPaymentMode IN ('DC', 'Debit Card') THEN 'Debit Card'
        WHEN PreferredPaymentMode IN ('E-wallet', 'E Wallet') THEN 'E Wallet'
        ELSE PreferredPaymentMode
    END AS payment_method_clean,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY payment_method_clean
ORDER BY churn_rate DESC, customers DESC;

-- By order category
SELECT PreferedOrderCat,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY PreferedOrderCat
ORDER BY churn_rate DESC, customers DESC;

-- By city tier
SELECT CityTier,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric), 4) AS churn_rate
FROM ecom_churn
GROUP BY CityTier
ORDER BY churn_rate DESC, customers DESC;

/* 4) Behaviour and satisfaction */
-- Complaints vs churn
SELECT Complain,
    COUNT(*) customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY Complain
ORDER BY churn_rate DESC;

-- Satisfaction score vs churn
SELECT SatisfactionScore,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY SatisfactionScore
ORDER BY churn_rate DESC, customers DESC;

-- Order frequency vs churn
SELECT OrderCount,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY OrderCount
ORDER BY churn_rate DESC, customers DESC;

/* 5) Tenure as retention proxy */
-- Lower churn with higher tenure? (retention = 1 - churn)
SELECT Tenure,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM ecom_churn
GROUP BY Tenure
ORDER BY Tenure;

/* 6) Quasi A/B: coupon vs no coupon */
-- Note: This is not a randomized test (customers self-select into using coupons)
-- but gives directional insight into coupon impact on churn
WITH base AS (
    SELECT CASE WHEN COALESCE(CouponUsed,0)>0 THEN 'Used coupon' ELSE 'No coupon' END AS coupon_group,
        Churn
    FROM ecom_churn
)
SELECT coupon_group,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM base
GROUP BY coupon_group
ORDER BY churn_rate;

/* 7) Top 5 worst churn segment combos (example) */
-- Combine device x payment to spot risky intersections
SELECT PreferredLoginDevice,
    PreferredPaymentMode,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY PreferredLoginDevice, PreferredPaymentMode
HAVING COUNT(*)>50
ORDER BY churn_rate DESC
LIMIT 5;

/* =======================================================
   8) Export-ready summaries (for Tableau dashboards)
   ======================================================= */

-- A) Churn by device
CREATE OR REPLACE VIEW churn_by_device AS
SELECT PreferredLoginDevice,
       COUNT(*) AS customers,
       ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY PreferredLoginDevice;

-- B) Churn by payment mode (cleaned)
CREATE OR REPLACE VIEW churn_by_payment AS
SELECT
    CASE
        WHEN PreferredPaymentMode IN ('COD', 'Cash on Delivery') THEN 'Cash on Delivery'
        WHEN PreferredPaymentMode IN ('CC', 'Credit Card') THEN 'Credit Card'
        WHEN PreferredPaymentMode IN ('DC', 'Debit Card') THEN 'Debit Card'
        WHEN PreferredPaymentMode IN ('E-wallet', 'E Wallet') THEN 'E Wallet'
        ELSE PreferredPaymentMode
    END AS payment_method_clean,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY payment_method_clean;

-- C) Churn by complaints
CREATE OR REPLACE VIEW churn_by_complaint AS
SELECT CASE WHEN Complain = 1 THEN 'Complaint' ELSE 'No Complaint' END AS complaint_status,
       COUNT(*) AS customers,
       ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY complaint_status;

/*
-- D) Churn by Satisfaction x Complaints
CREATE OR REPLACE VIEW churn_by_satisfaction_complaint AS
SELECT 
    SatisfactionScore,
    CASE WHEN Complain = 1 THEN 'Complaint' ELSE 'No Complaint' END AS complaint_status,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate
FROM ecom_churn
GROUP BY SatisfactionScore, complaint_status
ORDER BY SatisfactionScore DESC, complaint_status;
*/

/* Export views into csv files to connect to Tableau */
-- \COPY (SELECT * FROM churn_by_device) TO './exports/churn_by_device.csv' CSV HEADER;
-- \COPY (SELECT * FROM churn_by_payment) TO './exports/churn_by_payment.csv' CSV HEADER;
-- \COPY (SELECT * FROM churn_by_complaint) TO './exports/churn_by_complaint.csv' CSV HEADER;
-- \COPY (SELECT * FROM churn_by_satisfaction_complaint) TO './exports/churn_by_satisfaction_complaint.csv' CSV HEADER;
