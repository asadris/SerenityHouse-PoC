/******************************************************************************************
 SET 3 � FINANCIAL VALIDATION SUITE
 Serenity House Synthetic Data QA
 ------------------------------------------------------------------------------------------
 This script checks:
   � Missing rent charges
   � Missing payments
   � Overpayments
   � Underpayments / arrears
   � Waiver and assistance correctness
   � Duplicate charges or payments
   � Weekly billing alignment
   � Stays with no financial activity
******************************************************************************************/

/******************************************************************************************
 1. STAYS WITH NO RENT CHARGES
    Every stay should generate weekly rent charges.
******************************************************************************************/
SELECT 
    st.StayID,
    st.ResidentID,
    st.IntakeDate,
    st.ExitDate
FROM sh.Stay st
LEFT JOIN sh.RentCharge rc ON rc.StayID = st.StayID
GROUP BY st.StayID, st.ResidentID, st.IntakeDate, st.ExitDate
HAVING COUNT(rc.RentChargeID) = 0;


/******************************************************************************************
 2. STAYS WITH NO RENT PAYMENTS
    Not necessarily an error, but flagged for review.
******************************************************************************************/
SELECT 
    st.StayID,
    st.ResidentID,
    st.IntakeDate,
    st.ExitDate
FROM sh.Stay st
LEFT JOIN sh.RentPayment rp ON rp.StayID = st.StayID
GROUP BY st.StayID, st.ResidentID, st.IntakeDate, st.ExitDate
HAVING COUNT(rp.RentPaymentID) = 0;


/******************************************************************************************
 3. DUPLICATE RENT CHARGES (same StayID + ChargeDate)
******************************************************************************************/
SELECT 
    StayID,
    ChargeDate,
    COUNT(*) AS DuplicateCount
FROM sh.RentCharge
GROUP BY StayID, ChargeDate
HAVING COUNT(*) > 1;


/******************************************************************************************
 4. DUPLICATE RENT PAYMENTS (same StayID + PaymentDate + Amount)
******************************************************************************************/
SELECT 
    StayID,
    PaymentDate,
    Amount,
    COUNT(*) AS DuplicateCount
FROM sh.RentPayment
GROUP BY StayID, PaymentDate, Amount
HAVING COUNT(*) > 1;


/******************************************************************************************
 5. WEEKLY BILLING ALIGNMENT CHECK
    Ensures WeekNumber increments correctly and matches chronological order.
******************************************************************************************/
SELECT *
FROM (
    SELECT 
        StayID,
        ChargeDate,
        WeekNumber,
        LAG(WeekNumber) OVER (PARTITION BY StayID ORDER BY ChargeDate) AS PrevWeek
    FROM sh.RentCharge
) x
WHERE PrevWeek IS NOT NULL
  AND WeekNumber <> PrevWeek + 1;


/******************************************************************************************
 6. ARREARS CALCULATION � STAYS THAT OWE MONEY
    Total Charges - (Payments + Waivers + Assistance)
******************************************************************************************/
SELECT 
    st.StayID,
    st.ResidentID,
    SUM(rc.Amount) AS TotalCharges,
    SUM(rp.Amount) AS TotalPayments,
    SUM(rw.Amount) AS TotalWaivers,
    SUM(fa.Amount) AS TotalAssistance,
    SUM(rc.Amount)
      - ISNULL(SUM(rp.Amount), 0)
      - ISNULL(SUM(rw.Amount), 0)
      - ISNULL(SUM(fa.Amount), 0) AS BalanceOwed
FROM sh.Stay st
LEFT JOIN sh.RentCharge rc ON rc.StayID = st.StayID
LEFT JOIN sh.RentPayment rp ON rp.StayID = st.StayID
LEFT JOIN sh.RentWaiver rw ON rw.StayID = st.StayID
LEFT JOIN sh.FinancialAssistance fa ON fa.StayID = st.StayID
GROUP BY st.StayID, st.ResidentID
HAVING SUM(rc.Amount)
      - ISNULL(SUM(rp.Amount), 0)
      - ISNULL(SUM(rw.Amount), 0)
      - ISNULL(SUM(fa.Amount), 0) > 0;


/******************************************************************************************
 7. OVERPAYMENT DETECTION
    Payments + waivers + assistance exceed total charges.
******************************************************************************************/
SELECT 
    st.StayID,
    st.ResidentID,
    SUM(rc.Amount) AS TotalCharges,
    SUM(rp.Amount) AS TotalPayments,
    SUM(rw.Amount) AS TotalWaivers,
    SUM(fa.Amount) AS TotalAssistance,
    (ISNULL(SUM(rp.Amount), 0)
     + ISNULL(SUM(rw.Amount), 0)
     + ISNULL(SUM(fa.Amount), 0)) - SUM(rc.Amount) AS OverpaymentAmount
FROM sh.Stay st
LEFT JOIN sh.RentCharge rc ON rc.StayID = st.StayID
LEFT JOIN sh.RentPayment rp ON rp.StayID = st.StayID
LEFT JOIN sh.RentWaiver rw ON rw.StayID = st.StayID
LEFT JOIN sh.FinancialAssistance fa ON fa.StayID = st.StayID
GROUP BY st.StayID, st.ResidentID
HAVING (ISNULL(SUM(rp.Amount), 0)
     + ISNULL(SUM(rw.Amount), 0)
     + ISNULL(SUM(fa.Amount), 0)) > SUM(rc.Amount);


/******************************************************************************************
 8. WAIVER VALIDATION
    Ensures waivers do not exceed total charges.
******************************************************************************************/
SELECT 
    st.StayID,
    SUM(rc.Amount) AS TotalCharges,
    SUM(rw.Amount) AS TotalWaivers
FROM sh.Stay st
LEFT JOIN sh.RentCharge rc ON rc.StayID = st.StayID
LEFT JOIN sh.RentWaiver rw ON rw.StayID = st.StayID
GROUP BY st.StayID
HAVING SUM(rw.Amount) > SUM(rc.Amount);


/******************************************************************************************
 9. ASSISTANCE VALIDATION
    Ensures assistance does not exceed total charges.
******************************************************************************************/
SELECT 
    st.StayID,
    SUM(rc.Amount) AS TotalCharges,
    SUM(fa.Amount) AS TotalAssistance
FROM sh.Stay st
LEFT JOIN sh.RentCharge rc ON rc.StayID = st.StayID
LEFT JOIN sh.FinancialAssistance fa ON fa.StayID = st.StayID
GROUP BY st.StayID
HAVING SUM(fa.Amount) > SUM(rc.Amount);


/******************************************************************************************
 10. STAYS WITH NO FINANCIAL ACTIVITY AT ALL
     (No charges, no payments, no waivers, no assistance)
******************************************************************************************/
SELECT 
    st.StayID,
    st.ResidentID,
    st.IntakeDate,
    st.ExitDate
FROM sh.Stay st
LEFT JOIN sh.RentCharge rc ON rc.StayID = st.StayID
LEFT JOIN sh.RentPayment rp ON rp.StayID = st.StayID
LEFT JOIN sh.RentWaiver rw ON rw.StayID = st.StayID
LEFT JOIN sh.FinancialAssistance fa ON fa.StayID = st.StayID
GROUP BY st.StayID, st.ResidentID, st.IntakeDate, st.ExitDate
HAVING COUNT(rc.RentChargeID) = 0
   AND COUNT(rp.RentPaymentID) = 0
   AND COUNT(rw.RentWaiverID) = 0
   AND COUNT(fa.FinancialAssistanceID) = 0;