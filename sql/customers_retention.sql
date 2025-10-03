/* ================================================================
   COHORTS_RETENTION.SQL — Retention & Cohorts (PostgreSQL)
   Purpose: Create clean views for Tableau + analysis in SQL.
   Dataset: ecom_churn  (one row per customer)
   Notes:
     - Retention ≈ 1 - churn at each Tenure.
     - Coupon grouping is observational (not randomized).
   ================================================================ */

-- 1) Retention by Tenure (single-series line)
DROP VIEW IF EXISTS retention_by_tenure;
CREATE VIEW retention_by_tenure AS
SELECT Tenure,
    COUNT(*)                              AS customers,
    ROUND(AVG(Churn::numeric), 4)           AS churn_rate,
    ROUND(1 - AVG(Churn::numeric), 4)       AS retention_rate
FROM ecom_churn
WHERE Tenure IS NOT NULL
GROUP BY Tenure
ORDER BY Tenure;

-- 2) Retention by Tenure Band (0–3, 4–6, 7–12, 13+)
DROP VIEW IF EXISTS retention_by_tenure_band;
CREATE VIEW retention_by_tenure_band AS
WITH banded AS (
    SELECT *,
        CASE
            WHEN Tenure BETWEEN 0 AND 3  THEN '0-3'
            WHEN Tenure BETWEEN 4 AND 6  THEN '4-6'
            WHEN Tenure BETWEEN 7 AND 12 THEN '7-12'
            ELSE '13+'
        END AS tenure_band
    FROM ecom_churn
    WHERE Tenure IS NOT NULL
)
SELECT tenure_band,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric), 4) AS churn_rate,
    ROUND(1 - AVG(Churn::numeric), 4) AS retention_rate
FROM banded
GROUP BY tenure_band
ORDER BY CASE tenure_band
            WHEN '0-3' THEN 1
            WHEN '4-6' THEN 2
            WHEN '7-12' THEN 3
            ELSE 4
        END;

-- 3) Retention by Tenure × Coupon (two series)
DROP VIEW IF EXISTS retention_by_tenure_coupon;
CREATE VIEW retention_by_tenure_coupon AS
SELECT Tenure,
    CASE WHEN COALESCE(CouponUsed,0) > 0 THEN 'Used coupon'
        ELSE 'No coupon' END AS coupon_group,
    COUNT(*) AS customers,
    ROUND(1 - AVG(Churn::numeric), 4) AS retention_rate
FROM ecom_churn
WHERE Tenure IS NOT NULL
GROUP BY Tenure, coupon_group
ORDER BY Tenure, coupon_group;

-- 4) Retention by Tenure × Satisfaction band
DROP VIEW IF EXISTS retention_by_tenure_satisfaction;
CREATE VIEW retention_by_tenure_satisfaction AS
WITH satisfaction_score AS (
    SELECT *,
        CASE WHEN SatisfactionScore <= 3 THEN 'Low (less than 4)'
            WHEN SatisfactionScore = 4 THEN 'Medium (4)'
            ELSE 'High (5)' 
        END AS satisfaction_band
    FROM ecom_churn
    WHERE Tenure IS NOT NULL
)
SELECT Tenure,
    satisfaction_band,
    COUNT(*) AS customers,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM satisfaction_score
GROUP BY Tenure, satisfaction_band
ORDER BY Tenure, satisfaction_band;

-- 5) Retention matrix: Tenure × Device
DROP VIEW IF EXISTS retention_matrix_tenure_device;
CREATE VIEW retention_matrix_tenure_device AS
SELECT Tenure,
    PreferredLoginDevice,
    COUNT(*) AS customers,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM ecom_churn
WHERE Tenure IS NOT NULL
GROUP BY Tenure, PreferredLoginDevice
ORDER BY Tenure, PreferredLoginDevice;

-- 6) Retention matrix: Tenure × Payment Mode
DROP VIEW IF EXISTS retention_matrix_tenure_payment;
CREATE VIEW retention_matrix_tenure_payment AS
SELECT Tenure,
    CASE
        WHEN PreferredPaymentMode IN ('COD', 'Cash on Delivery') THEN 'Cash on Delivery'
        WHEN PreferredPaymentMode IN ('CC', 'Credit Card') THEN 'Credit Card'
        WHEN PreferredPaymentMode IN ('DC', 'Debit Card') THEN 'Debit Card'
        WHEN PreferredPaymentMode IN ('E-wallet', 'E Wallet') THEN 'E Wallet'
        ELSE PreferredPaymentMode
    END AS payment_method_clean,
    COUNT(*) AS customers,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM ecom_churn
WHERE Tenure IS NOT NULL
GROUP BY Tenure, payment_method_clean
ORDER BY Tenure, payment_method_clean;

-- 7) Early-tenure vs late-tenure comparison
DROP VIEW IF EXISTS retention_early_vs_late;
CREATE VIEW retention_early_vs_late AS
WITH banded AS (
    SELECT *,
        CASE WHEN Tenure <= 3 THEN 'Early (<=3)'
            WHEN Tenure > 3 THEN 'Later (>3)'
        END AS tenure_window
    FROM ecom_churn
    WHERE Tenure IS NOT NULL
)
SELECT tenure_window,
    COUNT(*) AS customers,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM banded
GROUP BY tenure_window
ORDER BY tenure_window;

-- 8) Bonus View: Retention for Null vs Valid Tenure
DROP VIEW IF EXISTS retention_null_vs_valid;
CREATE VIEW retention_null_vs_valid AS
SELECT 
    CASE 
        WHEN Tenure IS NULL THEN 'Null Tenure'
        ELSE 'Valid Tenure'
    END AS tenure_group,
    COUNT(*) AS customers,
    ROUND(1-AVG(Churn::numeric), 4) AS retention_rate
FROM ecom_churn
GROUP BY tenure_group

UNION ALL
SELECT 'Total Customers' AS tenure_group,
    COUNT(*) AS customers,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM ecom_churn;

-- 9) Export Results to CSV 

-- Save to relative path inside the project
-- \COPY (SELECT * FROM retention_by_tenure)
--   TO './exports/cohorts_retention/retention_by_tenure.csv' CSV HEADER;

-- Export retention by tenure band
-- \COPY (SELECT * FROM retention_by_tenure_band)
--   TO './exports/retention_by_tenure_band.csv' CSV HEADER;

-- Export retention by tenure coupon
-- \COPY (SELECT * FROM retention_by_tenure_coupon)
--   TO './exports/retention_by_tenure_coupon.csv' CSV HEADER;

-- Export retention by satisfaction
-- \COPY (SELECT * FROM retention_by_tenure_satisfaction)
--   TO './exports/retention_by_tenure_satisfaction.csv' CSV HEADER;

-- Export tenure × device retention
-- \COPY (SELECT * FROM retention_matrix_tenure_device)
--   TO './exports/retention_matrix_tenure_device.csv' CSV HEADER;

-- Export tenure × payment retention
-- \COPY (SELECT * FROM retention_matrix_tenure_payment)
--   TO './exports/retention_matrix_tenure_payment.csv' CSV HEADER;

-- Export early vs late tenure retention
-- \COPY (SELECT * FROM retention_early_vs_late)
--   TO './exports/retention_early_vs_late.csv' CSV HEADER;

-- Export null vs valid tenure retention
-- \COPY (SELECT * FROM retention_null_vs_valid)
--   TO './exports/retention_null_vs_valid.csv' CSV HEADER;