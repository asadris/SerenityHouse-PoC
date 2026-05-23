/******************************************************************************************
    SERENITY HOUSE - FULL WAREHOUSE ETL
    Source: sh schema (v6 OLTP)
    Target: dw schema (star schema)

    Run after: 01_star_schema.sql and generate_data.py
******************************************************************************************/

------------------------------------------------------------
-- 1. POPULATE DIMDATE (DATE SPINE)
------------------------------------------------------------
TRUNCATE TABLE dw.DimDate;

WITH DateSpine AS (
    SELECT CAST('2022-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d)
    FROM DateSpine
    WHERE d < '2030-12-31'
)
INSERT INTO dw.DimDate (DateKey, FullDate, Year, Quarter, Month, Day, DayOfWeek, WeekOfYear)
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DAY(d),
    DATEPART(WEEKDAY, d),
    DATEPART(WEEK, d)
FROM DateSpine
OPTION (MAXRECURSION 0);


------------------------------------------------------------
-- 2. DIMENSION LOADS
------------------------------------------------------------

-- DimResident
TRUNCATE TABLE dw.DimResident;

INSERT INTO dw.DimResident (
    ResidentID, FirstName, LastName, Gender, RaceEthnicity,
    DateOfBirth, City, StateProvince, County,
    OriginalCity, OriginalState, OriginalCounty
)
SELECT
    p.ResidentID,
    p.FirstName,
    p.LastName,
    p.Gender,
    CASE
        WHEN p.Race IS NOT NULL AND p.Ethnicity IS NOT NULL THEN p.Race + ' / ' + p.Ethnicity
        WHEN p.Race IS NOT NULL THEN p.Race
        WHEN p.Ethnicity IS NOT NULL THEN p.Ethnicity
        ELSE NULL
    END,
    p.DateOfBirth,
    p.HomeCity,
    p.HomeState,
    NULL,   -- County not in v6 schema
    p.OriginCity,
    p.OriginState,
    p.OriginCounty
FROM sh.Resident p;


-- DimHouse
TRUNCATE TABLE dw.DimHouse;

INSERT INTO dw.DimHouse (HouseID, HouseName, City, StateProvince, County)
SELECT
    HouseID,
    HouseName,
    City,
    StateCode,
    NULL    -- County not in v6 schema
FROM sh.House;


-- DimRoom
TRUNCATE TABLE dw.DimRoom;

INSERT INTO dw.DimRoom (RoomID, HouseID, RoomNumber, FloorNumber)
SELECT
    r.RoomID,
    r.HouseID,
    r.RoomNumber,
    NULL    -- FloorNumber not in v6 schema
FROM sh.Room r;


-- DimBed
TRUNCATE TABLE dw.DimBed;

INSERT INTO dw.DimBed (BedID, RoomID, BedLabel)
SELECT BedID, RoomID, BedLabel
FROM sh.Bed;


-- DimCaseManager
TRUNCATE TABLE dw.DimCaseManager;

INSERT INTO dw.DimCaseManager (CaseManagerID, FirstName, LastName, Email)
SELECT CaseManagerID, FirstName, LastName, Email
FROM sh.CaseManager;


-- DimReferralSource
TRUNCATE TABLE dw.DimReferralSource;

INSERT INTO dw.DimReferralSource (ReferralSourceID, Name, Category)
SELECT ReferralSourceID, SourceName, SourceCategory
FROM sh.ReferralSource;


-- DimServiceType
TRUNCATE TABLE dw.DimServiceType;

INSERT INTO dw.DimServiceType (ServiceTypeID, ServiceName, Category, IsRequired)
SELECT
    ServiceTypeID,
    ServiceName,
    NULL,       -- Category not in v6 schema
    IsRequired
FROM sh.ServiceType;


-- DimIncidentType
TRUNCATE TABLE dw.DimIncidentType;

INSERT INTO dw.DimIncidentType (IncidentTypeID, IncidentName, SeverityLevel)
SELECT
    IncidentTypeID,
    TypeName,
    Severity
FROM sh.IncidentType;


------------------------------------------------------------
-- 3. FACT LOADS
------------------------------------------------------------

-- FactStay
-- Outcome rows are pivoted: one row per stay with destination, employment, completion flag
TRUNCATE TABLE dw.FactStay;

INSERT INTO dw.FactStay (
    StayID, ResidentKey, BedKey, CaseManagerKey, ReferralSourceKey,
    IntakeDateKey, ExitDateKey,
    IsSuccessfulExit, OutcomeCategory, DestinationType, EmploymentStatusAtExit
)
SELECT
    s.StayID,
    dp.ResidentKey,
    db.BedKey,
    dcm.CaseManagerKey,
    drs.ReferralSourceKey,
    CONVERT(INT, FORMAT(s.IntakeDate, 'yyyyMMdd')),
    CONVERT(INT, FORMAT(s.ExitDate, 'yyyyMMdd')),
    CASE WHEN o_comp.OutcomeValue = 'Yes' THEN 1 ELSE 0 END,
    s.StayStatus,
    o_dest.OutcomeValue,
    o_emp.OutcomeValue
FROM sh.Stay s
JOIN  dw.DimResident  dp  ON dp.ResidentID   = s.ResidentID
JOIN  dw.DimBed          db  ON db.BedID            = s.BedID
LEFT JOIN dw.DimCaseManager  dcm ON dcm.CaseManagerID  = s.CaseManagerID
LEFT JOIN dw.DimReferralSource drs ON drs.ReferralSourceID = s.ReferralSourceID
LEFT JOIN sh.Outcome o_dest ON o_dest.StayID = s.StayID AND o_dest.OutcomeType = 'Exit Destination'
LEFT JOIN sh.Outcome o_emp  ON o_emp.StayID  = s.StayID AND o_emp.OutcomeType  = 'Employment at Exit'
LEFT JOIN sh.Outcome o_comp ON o_comp.StayID = s.StayID AND o_comp.OutcomeType = 'Program Completion'
;


-- FactServiceEncounter
TRUNCATE TABLE dw.FactServiceEncounter;

INSERT INTO dw.FactServiceEncounter (
    ServiceEncounterID, StayKey, ResidentKey, ServiceTypeKey,
    EncounterDateKey, DurationMinutes, AttendanceStatus
)
SELECT
    se.EncounterID,
    fs.StayKey,
    dp.ResidentKey,
    dst.ServiceTypeKey,
    CONVERT(INT, FORMAT(se.EncounterDate, 'yyyyMMdd')),
    NULL,   -- DurationMinutes not in v6 schema
    CASE WHEN se.Attended = 1 THEN 'Attended' ELSE 'Absent' END
FROM sh.ServiceEncounter se
JOIN dw.FactStay        fs  ON fs.StayID        = se.StayID
JOIN dw.DimResident  dp  ON dp.ResidentKey = fs.ResidentKey
JOIN dw.DimServiceType  dst ON dst.ServiceTypeID = se.ServiceTypeID;


-- FactDrugTest
TRUNCATE TABLE dw.FactDrugTest;

INSERT INTO dw.FactDrugTest (
    DrugTestID, StayKey, ResidentKey, TestDateKey,
    TestType, Result, SubstancesDetected
)
SELECT
    dt.DrugTestID,
    fs.StayKey,
    fs.ResidentKey,
    CONVERT(INT, FORMAT(dt.TestDate, 'yyyyMMdd')),
    dt.TestType,
    dt.Result,
    dt.SubstancesDetected
FROM sh.DrugTest dt
JOIN dw.FactStay fs ON fs.StayID = dt.StayID;


-- FactIncident
TRUNCATE TABLE dw.FactIncident;

INSERT INTO dw.FactIncident (
    IncidentID, StayKey, ResidentKey, IncidentTypeKey,
    IncidentDateKey, Description
)
SELECT
    i.IncidentID,
    fs.StayKey,
    fs.ResidentKey,
    dit.IncidentTypeKey,
    CONVERT(INT, FORMAT(i.IncidentDate, 'yyyyMMdd')),
    i.Description
FROM sh.Incident i
JOIN dw.FactStay       fs  ON fs.StayID          = i.StayID
JOIN dw.DimIncidentType dit ON dit.IncidentTypeID = i.IncidentTypeID;


-- FactEmploymentSnapshot
-- v6 stores actual HourlyWage and HoursPerWeek; we band them for the DW
TRUNCATE TABLE dw.FactEmploymentSnapshot;

INSERT INTO dw.FactEmploymentSnapshot (
    SnapshotID, StayKey, SnapshotDateKey,
    EmploymentStatus, EmployerName, WageBand, HoursPerWeekBand
)
SELECT
    es.SnapshotID,
    fs.StayKey,
    CONVERT(INT, FORMAT(es.SnapshotDate, 'yyyyMMdd')),
    es.EmploymentStatus,
    es.Employer,
    CASE
        WHEN es.HourlyWage IS NULL   THEN NULL
        WHEN es.HourlyWage < 12      THEN 'Under $12/hr'
        WHEN es.HourlyWage < 15      THEN '$12-$14.99/hr'
        WHEN es.HourlyWage < 20      THEN '$15-$19.99/hr'
        WHEN es.HourlyWage < 25      THEN '$20-$24.99/hr'
        ELSE '$25+/hr'
    END,
    CASE
        WHEN es.HoursPerWeek IS NULL THEN NULL
        WHEN es.HoursPerWeek < 20   THEN 'Under 20 hrs'
        WHEN es.HoursPerWeek < 35   THEN '20-34 hrs'
        ELSE '35+ hrs (Full-Time)'
    END
FROM sh.StayEmploymentSnapshot es
JOIN dw.FactStay fs ON fs.StayID = es.StayID;


-- FactRentCharge
TRUNCATE TABLE dw.FactRentCharge;

INSERT INTO dw.FactRentCharge (RentChargeID, StayKey, ChargeDateKey, Amount, WeekNumber)
SELECT
    rc.ChargeID,
    fs.StayKey,
    CONVERT(INT, FORMAT(rc.ChargeDate, 'yyyyMMdd')),
    rc.AmountCharged,
    DATEDIFF(WEEK, s.IntakeDate, rc.ChargeDate) + 1
FROM sh.RentCharge rc
JOIN dw.FactStay fs ON fs.StayID = rc.StayID
JOIN sh.Stay     s  ON s.StayID  = rc.StayID;


-- FactRentPayment
TRUNCATE TABLE dw.FactRentPayment;

INSERT INTO dw.FactRentPayment (RentPaymentID, StayKey, PaymentDateKey, Amount, PaymentMethod)
SELECT
    rp.PaymentID,
    fs.StayKey,
    CONVERT(INT, FORMAT(rp.PaymentDate, 'yyyyMMdd')),
    rp.AmountPaid,
    rp.PaymentMethod
FROM sh.RentPayment rp
JOIN dw.FactStay fs ON fs.StayID = rp.StayID;


-- FactRentWaiver
TRUNCATE TABLE dw.FactRentWaiver;

INSERT INTO dw.FactRentWaiver (RentWaiverID, StayKey, WaiverDateKey, Amount, Reason, ApprovedBy)
SELECT
    rw.WaiverID,
    fs.StayKey,
    CONVERT(INT, FORMAT(rw.WaiverDate, 'yyyyMMdd')),
    rw.AmountWaived,
    rw.WaiverReason,
    rw.ApprovedBy
FROM sh.RentWaiver rw
JOIN dw.FactStay fs ON fs.StayID = rw.StayID;


-- FactFinancialAssistance (from ProgramPayment + FinancialAssistanceProgram)
TRUNCATE TABLE dw.FactFinancialAssistance;

INSERT INTO dw.FactFinancialAssistance (
    FinancialAssistanceID, StayKey, AssistanceDateKey, Amount, Source, Notes
)
SELECT
    pp.ProgramPaymentID,
    fs.StayKey,
    CONVERT(INT, FORMAT(pp.PaymentDate, 'yyyyMMdd')),
    pp.AmountPaid,
    fap.ProgramName,
    pp.Notes
FROM sh.ProgramPayment pp
JOIN sh.FinancialAssistanceProgram fap ON fap.ProgramID = pp.ProgramID
JOIN dw.FactStay fs ON fs.StayID = pp.StayID;


-- DimDonor
TRUNCATE TABLE dw.DimDonor;

INSERT INTO dw.DimDonor (
    DonorID, DonorType, OrganizationName, FirstName, LastName,
    City, IsRecurring, IsAnonymous
)
SELECT
    d.DonorID,
    d.DonorType,
    d.OrganizationName,
    d.FirstName,
    d.LastName,
    d.City,
    d.IsRecurring,
    CASE WHEN d.DonorType = 'Anonymous' THEN 1 ELSE 0 END
FROM sh.Donor d;


-- DimFundraisingEvent
-- Row 0 = sentinel "General Fund" for donations not linked to a specific event
TRUNCATE TABLE dw.DimFundraisingEvent;

INSERT INTO dw.DimFundraisingEvent (EventID, EventName, EventType, EventDate, Goal, IsGeneralFund)
VALUES (0, 'General Fund', 'General', NULL, NULL, 1);

INSERT INTO dw.DimFundraisingEvent (EventID, EventName, EventType, EventDate, Goal, IsGeneralFund)
SELECT
    e.EventID,
    e.EventName,
    e.EventType,
    e.EventDate,
    e.Goal,
    0
FROM sh.FundraisingEvent e;


-- FactDonation
-- NULL EventID (general fund) maps to EventID = 0
TRUNCATE TABLE dw.FactDonation;

INSERT INTO dw.FactDonation (
    DonationID, DonorID, FundraisingEventID, DonationDateKey, Amount, PaymentMethod
)
SELECT
    fd.DonationID,
    fd.DonorID,
    ISNULL(fd.EventID, 0),
    CONVERT(INT, FORMAT(fd.DonationDate, 'yyyyMMdd')),
    fd.Amount,
    fd.DonationType
FROM sh.FundraisingDonation fd;


PRINT 'ETL COMPLETE - Warehouse successfully loaded.';
