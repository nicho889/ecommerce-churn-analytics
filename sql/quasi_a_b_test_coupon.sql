/* ================================================================
   A_B_TEST_COUPON.SQL — Quasi A/B test: Coupon vs No Coupon
   Purpose: Measure churn & retention for coupon customers vs non-customers.
   Dataset: ecom_churn (already created in exploration.sql)
   Notes:
     - This is NOT a true randomized A/B test (customers self-select).
     - Insights are directional only.
   ================================================================ */

-- 1) Coupon groups summary (churn/retention by coupon use)
DROP VIEW IF EXISTS coupon_groups CASCADE;
CREATE VIEW coupon_groups AS
SELECT CASE WHEN COALESCE(CouponUsed,0)>0 THEN 'Used coupon'
    ELSE 'No coupon' END AS coupon_group,
    COUNT(*) AS customers,
    SUM(Churn) AS churned,
    ROUND(AVG(Churn::numeric),4) AS churn_rate,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM ecom_churn
GROUP BY coupon_group
ORDER BY churn_rate;

-- 2) Coupon effect by device (to see if impact differs by device)
DROP VIEW IF EXISTS coupon_effect_by_device;
CREATE VIEW coupon_effect_by_device AS
SELECT PreferredLoginDevice,
    CASE WHEN COALESCE(CouponUsed,0)>0 THEN 'Used coupon'
        ELSE 'No coupon' END AS coupon_group,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM ecom_churn
GROUP BY PreferredLoginDevice, coupon_group
ORDER BY PreferredLoginDevice, coupon_group;

-- 3) Coupon effect by satisfaction band
DROP VIEW IF EXISTS coupon_effect_by_satisfaction;
CREATE VIEW coupon_effect_by_satisfaction AS
WITH satisfaction_score AS (
    SELECT *,
        CASE WHEN SatisfactionScore <= 3 THEN 'Low (<=3)'
            WHEN SatisfactionScore = 4 THEN 'Medium (4)'
            ELSE 'High (5)' END AS satisfaction_band
    FROM ecom_churn
)
SELECT satisfaction_band,
    CASE WHEN COALESCE(CouponUsed,0)>0 THEN 'Used coupon'
        ELSE 'No coupon' END AS coupon_group,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM satisfaction_score
GROUP BY satisfaction_band, coupon_group
ORDER BY satisfaction_band, coupon_group;

-- 4) Coupon effect by tenure bands
DROP VIEW IF EXISTS coupon_by_tenure_band;
CREATE VIEW coupon_by_tenure_band AS
WITH banded AS (
    SELECT *,
        CASE 
            WHEN Tenure BETWEEN 0 AND 3 THEN '0-3'
            WHEN Tenure BETWEEN 4 AND 6 THEN '4-6'
            WHEN Tenure BETWEEN 7 AND 12 THEN '7-12'
            ELSE '13+'
        END AS tenure_band,
        CASE WHEN COALESCE(CouponUsed,0)>0 THEN 'Used coupon'
        ELSE 'No coupon' END AS coupon_group
    FROM ecom_churn
    WHERE Tenure IS NOT NULL
)
SELECT tenure_band,
    coupon_group,
    COUNT(*) AS customers,
    ROUND(AVG(Churn::numeric),4) AS churn_rate,
    ROUND(1-AVG(Churn::numeric),4) AS retention_rate
FROM banded
GROUP BY tenure_band, coupon_group
ORDER BY CASE tenure_band
            WHEN '0-3' THEN 1
            WHEN '4-6' THEN 2
            WHEN '7-12' THEN 3
            ELSE 4
        END,
        coupon_group;

-- 5) Coupon effect by payment method
DROP VIEW IF EXISTS coupon_effect_by_payment;
CREATE VIEW coupon_effect_by_payment AS
SELECT 
    CASE
        WHEN PreferredPaymentMode IN ('COD', 'Cash on Delivery') THEN 'Cash on Delivery'
        WHEN PreferredPaymentMode IN ('CC', 'Credit Card') THEN 'Credit Card'
        WHEN PreferredPaymentMode IN ('DC', 'Debit Card') THEN 'Debit Card'
        ELSE PreferredPaymentMode
    END AS payment_method_clean,
    CASE WHEN COALESCE(CouponUsed,0)>0 THEN 'Used Coupon'
         ELSE 'No Coupon' END AS coupon_group,
    COUNT(*)                          AS customers,
    ROUND(AVG(Churn::numeric),4)      AS churn_rate,
    ROUND(1-AVG(Churn::numeric),4)    AS retention_rate
FROM ecom_churn
GROUP BY payment_method_clean, coupon_group
ORDER BY payment_method_clean, coupon_group;

-- 6) Effect-size KPIs (risk difference, retention uplift, RR, OR, CI)
DROP VIEW IF EXISTS coupon_effect_kpis;
CREATE VIEW coupon_effect_kpis AS
WITH totals AS (
    SELECT
        CASE WHEN COALESCE(CouponUsed,0) > 0 THEN 'Used Coupon'
             ELSE 'No Coupon' END AS coupon_group,
        COUNT(*)::numeric AS customers,
        SUM(Churn)::numeric AS churned,
        COUNT(*) - SUM(Churn) AS retained
    FROM ecom_churn
    GROUP BY coupon_group
),
rates AS (
    SELECT
        (SELECT customers FROM totals WHERE coupon_group = 'Used Coupon')     AS customers_treated,
        (SELECT churned   FROM totals WHERE coupon_group = 'Used Coupon')     AS churned_treated,
        (SELECT customers FROM totals WHERE coupon_group = 'No Coupon')       AS customers_control,
        (SELECT churned   FROM totals WHERE coupon_group = 'No Coupon')       AS churned_control
),
calc AS (
    SELECT
        customers_treated, churned_treated, customers_control, churned_control,

        (churned_treated::numeric / customers_treated)                        AS churn_rate_treated,
        (churned_control::numeric / customers_control)                        AS churn_rate_control,

        (1 - churned_treated::numeric / customers_treated)                    AS retention_rate_treated,
        (1 - churned_control::numeric / customers_control)                    AS retention_rate_control,

        (churned_treated::numeric / customers_treated) 
          - (churned_control::numeric / customers_control)                    AS churn_rate_difference,

        ((1 - churned_treated::numeric / customers_treated) 
          - (1 - churned_control::numeric / customers_control))               AS retention_rate_difference,

        (churned_treated::numeric / customers_treated) 
          / NULLIF((churned_control::numeric / customers_control),0)          AS relative_risk_churn,

        ((churned_treated + 0.5) / (customers_treated - churned_treated + 0.5)) 
          / ((churned_control + 0.5) / (customers_control - churned_control + 0.5)) AS odds_ratio_churn,

        sqrt( ( (churned_treated::numeric/customers_treated) * (1 - churned_treated::numeric/customers_treated) / customers_treated )
            + ( (churned_control::numeric/customers_control) * (1 - churned_control::numeric/customers_control) / customers_control ) ) AS standard_error_difference
    FROM rates
)
SELECT
    customers_treated,
    churned_treated,
    customers_control,
    churned_control,

    ROUND(churn_rate_treated,6)              AS churn_rate_treated,
    ROUND(churn_rate_control,6)              AS churn_rate_control,

    ROUND(retention_rate_treated,6)          AS retention_rate_treated,
    ROUND(retention_rate_control,6)          AS retention_rate_control,

    ROUND(churn_rate_difference,6)           AS churn_rate_difference,
    ROUND(retention_rate_difference,6)       AS retention_rate_difference,

    ROUND(relative_risk_churn,6)             AS relative_risk_churn,
    ROUND(odds_ratio_churn,6)                AS odds_ratio_churn,

    ROUND(churn_rate_difference - 1.96*standard_error_difference,6) AS churn_rate_difference_confidence_low,
    ROUND(churn_rate_difference + 1.96*standard_error_difference,6) AS churn_rate_difference_confidence_high
FROM calc;

-- 7) Export-ready CSVs
-- Run in psql with \COPY, uncomment to use.

-- \COPY (SELECT * FROM coupon_groups)
--   TO './exports/coupon_groups.csv' CSV HEADER;

-- \COPY (SELECT * FROM coupon_effect_by_device)
--   TO './exports/coupon_effect_by_device.csv' CSV HEADER;

-- \COPY (SELECT * FROM coupon_effect_by_satisfaction)
--   TO './exports/coupon_effect_by_satisfaction.csv' CSV HEADER;

-- \COPY (SELECT * FROM coupon_by_tenure_band) 
--   TO './exports/a_b_test_coupon/coupon_by_tenure_band.csv' CSV HEADER;

-- \COPY (SELECT * FROM coupon_effect_by_payment) 
--   TO './exports/a_b_test_coupon/coupon_effect_by_payment.csv' CSV HEADER;

-- \COPY (SELECT * FROM coupon_effect_kpis) 
--   TO './exports/a_b_test_coupon/coupon_effect_kpis.csv' CSV HEADER;