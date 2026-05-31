-- ============================================================
-- Arrears Page Validation Queries
-- Run against Serenity1 to verify Power BI Arrears page values.
--
-- "Current resident" = IntakeDateKey <= @TodayKey AND ExitDateKey >= @TodayKey
--
-- This date-range approach is required (not OutcomeCategory = 'Active').
-- OutcomeCategory is a snapshot from data-generation time and becomes stale
-- as the current date advances. The date-range check recalculates correctly
-- on any viewing date between START_DATE (2022-01-01) and END_DATE (2029-12-31).
-- ============================================================

DECLARE @TodayKey INT = CAST(CONVERT(VARCHAR, GETDATE(), 112) AS INT);

-- 1. Total Charges (current residents, <= today)
SELECT SUM(rc.Amount) AS TotalCharges
FROM dw.FactRentCharge rc
JOIN dw.FactStay fs ON rc.StayKey = fs.StayKey
WHERE rc.ChargeDateKey <= @TodayKey
  AND fs.IntakeDateKey  <= @TodayKey
  AND fs.ExitDateKey    >= @TodayKey;

-- 2. Total Payments (current residents, <= today)
SELECT SUM(rp.Amount) AS TotalPayments
FROM dw.FactRentPayment rp
JOIN dw.FactStay fs ON rp.StayKey = fs.StayKey
WHERE rp.PaymentDateKey <= @TodayKey
  AND fs.IntakeDateKey   <= @TodayKey
  AND fs.ExitDateKey     >= @TodayKey;

-- 3. Total Waivers (current residents, <= today)
SELECT SUM(rw.Amount) AS TotalWaivers
FROM dw.FactRentWaiver rw
JOIN dw.FactStay fs ON rw.StayKey = fs.StayKey
WHERE rw.WaiverDateKey <= @TodayKey
  AND fs.IntakeDateKey  <= @TodayKey
  AND fs.ExitDateKey    >= @TodayKey;

-- 4. Total Assistance (current residents, <= today)
SELECT SUM(fa.Amount) AS TotalAssistance
FROM dw.FactFinancialAssistance fa
JOIN dw.FactStay fs ON fa.StayKey = fs.StayKey
WHERE fa.AssistanceDateKey <= @TodayKey
  AND fs.IntakeDateKey      <= @TodayKey
  AND fs.ExitDateKey        >= @TodayKey;

-- 5. Arrears per resident — should match Arrears page table row-for-row
--    Pre-aggregate each fact table in a subquery before joining.
--    Joining multiple fact tables directly causes row fan-out (rows multiply)
--    and inflates all totals incorrectly.
SELECT
    dr.FirstName + ' ' + dr.LastName               AS FullName,
    ISNULL(rc.TotalCharges,    0)                   AS TotalCharges,
    ISNULL(rp.TotalPayments,   0)                   AS TotalPayments,
    ISNULL(rw.TotalWaivers,    0)                   AS TotalWaivers,
    ISNULL(fa.TotalAssistance, 0)                   AS TotalAssistance,
    ISNULL(rc.TotalCharges,    0)
        - ISNULL(rp.TotalPayments,   0)
        - ISNULL(rw.TotalWaivers,    0)
        - ISNULL(fa.TotalAssistance, 0)             AS Arrears
FROM dw.FactStay fs
JOIN dw.DimResident dr ON fs.ResidentKey = dr.ResidentKey
LEFT JOIN (
    SELECT StayKey, SUM(Amount) AS TotalCharges
    FROM dw.FactRentCharge
    WHERE ChargeDateKey <= @TodayKey
    GROUP BY StayKey
) rc ON rc.StayKey = fs.StayKey
LEFT JOIN (
    SELECT StayKey, SUM(Amount) AS TotalPayments
    FROM dw.FactRentPayment
    WHERE PaymentDateKey <= @TodayKey
    GROUP BY StayKey
) rp ON rp.StayKey = fs.StayKey
LEFT JOIN (
    SELECT StayKey, SUM(Amount) AS TotalWaivers
    FROM dw.FactRentWaiver
    WHERE WaiverDateKey <= @TodayKey
    GROUP BY StayKey
) rw ON rw.StayKey = fs.StayKey
LEFT JOIN (
    SELECT StayKey, SUM(Amount) AS TotalAssistance
    FROM dw.FactFinancialAssistance
    WHERE AssistanceDateKey <= @TodayKey
    GROUP BY StayKey
) fa ON fa.StayKey = fs.StayKey
WHERE fs.IntakeDateKey <= @TodayKey
  AND fs.ExitDateKey   >= @TodayKey
ORDER BY Arrears DESC;
