USE Serenity1;
GO

PRINT '=========================================';
PRINT '   STARTING DATA WAREHOUSE RELOAD';
PRINT '=========================================';

------------------------------------------------------------
-- 1. CLEAR DW TABLES IN CORRECT ORDER
------------------------------------------------------------

PRINT '--- Clearing DW FactDonation ---';
IF OBJECT_ID('dw.FactDonation', 'U') IS NOT NULL
BEGIN
    TRUNCATE TABLE dw.FactDonation;
END

PRINT '--- Clearing DW DimDonor ---';
IF OBJECT_ID('dw.DimDonor', 'U') IS NOT NULL
BEGIN
    TRUNCATE TABLE dw.DimDonor;
END

PRINT '--- Clearing DW DimFundraisingEvent ---';
IF OBJECT_ID('dw.DimFundraisingEvent', 'U') IS NOT NULL
BEGIN
    TRUNCATE TABLE dw.DimFundraisingEvent;
END

PRINT 'DW tables cleared.';
PRINT '-----------------------------------------';


------------------------------------------------------------
-- 2. RELOAD DIMDONOR
------------------------------------------------------------

PRINT '--- Loading dw.DimDonor ---';

INSERT INTO dw.DimDonor
(
    DonorID,
    DonorName,
    DonorType,
    Email,
    Phone,
    City,
    StateProvince,
    PostalCode,
    CashOnSite,
    IsAnonymous
)
SELECT
    d.DonorID,
    d.DonorName,
    d.DonorType,
    d.Email,
    d.Phone,
    d.City,
    d.StateProvince,
    d.PostalCode,
    d.CashOnSite,
    CASE WHEN d.DonorName = 'Anonymous' THEN 1 ELSE 0 END AS IsAnonymous
FROM sh.Donor AS d;

PRINT 'dw.DimDonor loaded.';
PRINT '-----------------------------------------';


------------------------------------------------------------
-- 3. RELOAD DIMFUNDRAISINGEVENT
------------------------------------------------------------

PRINT '--- Loading dw.DimFundraisingEvent ---';

INSERT INTO dw.DimFundraisingEvent
(
    FundraisingEventID,
    EventName,
    EventDate,
    Location,
    TargetAmount,
    IsGeneralFund
)
SELECT
    e.FundraisingEventID,
    e.EventName,
    e.EventDate,
    e.Location,
    e.TargetAmount,
    CASE WHEN e.EventName = 'General Fund' THEN 1 ELSE 0 END AS IsGeneralFund
FROM sh.FundraisingEvent AS e;

PRINT 'dw.DimFundraisingEvent loaded.';
PRINT '-----------------------------------------';


------------------------------------------------------------
-- 4. RELOAD FACTDONATION
------------------------------------------------------------

PRINT '--- Loading dw.FactDonation ---';

INSERT INTO dw.FactDonation
(
    DonationID,
    DonorID,
    FundraisingEventID,
    DonationDateKey,
    Amount,
    PaymentMethod
)
SELECT
    fd.FundraisingDonationID AS DonationID,
    fd.DonorID,
    fd.FundraisingEventID,
    d.DateKey AS DonationDateKey,
    fd.Amount,
    fd.PaymentMethod
FROM sh.FundraisingDonation AS fd
JOIN dw.DimDate AS d
    ON d.FullDate = fd.DonationDate;

PRINT 'dw.FactDonation loaded.';
PRINT '-----------------------------------------';


------------------------------------------------------------
-- 5. DONE
------------------------------------------------------------

PRINT '=========================================';
PRINT '   DATA WAREHOUSE RELOAD COMPLETE';
PRINT '=========================================';
GO