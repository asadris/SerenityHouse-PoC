------------------------------------------------------------
-- FULL WAREHOUSE BUILD SCRIPT (END-TO-END)
------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dw')
    EXEC('CREATE SCHEMA dw');
GO

PRINT 'Dropping existing DW tables...';

DROP TABLE IF EXISTS dw.FactDonation;
DROP TABLE IF EXISTS dw.FactFinancialAssistance;
DROP TABLE IF EXISTS dw.DimDonor;
DROP TABLE IF EXISTS dw.DimFundraisingEvent;
DROP TABLE IF EXISTS dw.FactRentWaiver;
DROP TABLE IF EXISTS dw.FactRentPayment;
DROP TABLE IF EXISTS dw.FactRentCharge;
DROP TABLE IF EXISTS dw.FactEmploymentSnapshot;
DROP TABLE IF EXISTS dw.FactIncident;
DROP TABLE IF EXISTS dw.FactDrugTest;
DROP TABLE IF EXISTS dw.FactServiceEncounter;
DROP TABLE IF EXISTS dw.FactStay;

DROP TABLE IF EXISTS dw.DimIncidentType;
DROP TABLE IF EXISTS dw.DimServiceType;
DROP TABLE IF EXISTS dw.DimReferralSource;
DROP TABLE IF EXISTS dw.DimCaseManager;
DROP TABLE IF EXISTS dw.DimBed;
DROP TABLE IF EXISTS dw.DimRoom;
DROP TABLE IF EXISTS dw.DimHouse;
DROP TABLE IF EXISTS dw.DimResident;
DROP TABLE IF EXISTS dw.DimDate;

PRINT 'Recreating DW tables...';

------------------------------------------------------------
-- DIMENSIONS
------------------------------------------------------------

-- DimResident
CREATE TABLE dw.DimResident (
    ResidentKey INT IDENTITY(1,1) PRIMARY KEY,
    ResidentID INT NOT NULL,
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Gender NVARCHAR(50),
    RaceEthnicity NVARCHAR(100),
    DateOfBirth DATE,
    AgeAtIntake AS DATEDIFF(YEAR, DateOfBirth, GETDATE()),
    City NVARCHAR(100),
    StateProvince NVARCHAR(50),
    County NVARCHAR(100),
    OriginalCity NVARCHAR(100),
    OriginalState NVARCHAR(50),
    OriginalCounty NVARCHAR(100)
);

-- DimDate
CREATE TABLE dw.DimDate (
    DateKey INT PRIMARY KEY,
    FullDate DATE NOT NULL,
    Year INT,
    Quarter INT,
    Month INT,
    Day INT,
    DayOfWeek INT,
    WeekOfYear INT
);

-- DimHouse
CREATE TABLE dw.DimHouse (
    HouseKey INT IDENTITY(1,1) PRIMARY KEY,
    HouseID INT NOT NULL,
    HouseName NVARCHAR(200),
    City NVARCHAR(100),
    StateProvince NVARCHAR(50),
    County NVARCHAR(100)
);

-- DimRoom
CREATE TABLE dw.DimRoom (
    RoomKey INT IDENTITY(1,1) PRIMARY KEY,
    RoomID INT NOT NULL,
    HouseID INT NOT NULL,
    RoomNumber NVARCHAR(50),
    FloorNumber INT
);

-- DimBed
CREATE TABLE dw.DimBed (
    BedKey INT IDENTITY(1,1) PRIMARY KEY,
    BedID INT NOT NULL,
    RoomID INT NOT NULL,
    BedLabel NVARCHAR(10)
);

-- DimCaseManager
CREATE TABLE dw.DimCaseManager (
    CaseManagerKey INT IDENTITY(1,1) PRIMARY KEY,
    CaseManagerID INT NOT NULL,
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Email NVARCHAR(200)
);

-- DimReferralSource
CREATE TABLE dw.DimReferralSource (
    ReferralSourceKey INT IDENTITY(1,1) PRIMARY KEY,
    ReferralSourceID INT NOT NULL,
    Name NVARCHAR(200),
    Category NVARCHAR(100)
);

-- DimServiceType
CREATE TABLE dw.DimServiceType (
    ServiceTypeKey INT IDENTITY(1,1) PRIMARY KEY,
    ServiceTypeID INT NOT NULL,
    ServiceName NVARCHAR(200),
    Category NVARCHAR(100),
    IsRequired BIT
);

-- DimIncidentType
CREATE TABLE dw.DimIncidentType (
    IncidentTypeKey INT IDENTITY(1,1) PRIMARY KEY,
    IncidentTypeID INT NOT NULL,
    IncidentName NVARCHAR(200),
    SeverityLevel NVARCHAR(20)   -- 'Low', 'Medium', 'High', 'Critical'
);

------------------------------------------------------------
-- FACTS
------------------------------------------------------------

-- FactStay
CREATE TABLE dw.FactStay (
    StayKey INT IDENTITY(1,1) PRIMARY KEY,
    StayID INT NOT NULL,
    ResidentKey INT NOT NULL,
    BedKey INT NOT NULL,
    CaseManagerKey INT NULL,
    ReferralSourceKey INT NULL,
    IntakeDateKey INT NOT NULL,
    ExitDateKey INT NULL,
    IsSuccessfulExit BIT,
    OutcomeCategory NVARCHAR(100),
    DestinationType NVARCHAR(200),
    EmploymentStatusAtExit NVARCHAR(200)
);

-- FactServiceEncounter
CREATE TABLE dw.FactServiceEncounter (
    ServiceEncounterKey INT IDENTITY(1,1) PRIMARY KEY,
    ServiceEncounterID INT NOT NULL,
    StayKey INT NOT NULL,
    ResidentKey INT NOT NULL,
    ServiceTypeKey INT NOT NULL,
    EncounterDateKey INT NOT NULL,
    DurationMinutes INT,
    AttendanceStatus NVARCHAR(50)
);

-- FactDrugTest
CREATE TABLE dw.FactDrugTest (
    DrugTestKey INT IDENTITY(1,1) PRIMARY KEY,
    DrugTestID INT NOT NULL,
    StayKey INT NOT NULL,
    ResidentKey INT NOT NULL,
    TestDateKey INT NOT NULL,
    TestType NVARCHAR(100),
    Result NVARCHAR(50),
    SubstancesDetected NVARCHAR(200)
);

-- FactIncident
CREATE TABLE dw.FactIncident (
    IncidentKey INT IDENTITY(1,1) PRIMARY KEY,
    IncidentID INT NOT NULL,
    StayKey INT NOT NULL,
    ResidentKey INT NOT NULL,
    IncidentTypeKey INT NOT NULL,
    IncidentDateKey INT NOT NULL,
    Description NVARCHAR(MAX)
);

-- FactEmploymentSnapshot
CREATE TABLE dw.FactEmploymentSnapshot (
    EmploymentSnapshotKey INT IDENTITY(1,1) PRIMARY KEY,
    SnapshotID INT NOT NULL,
    StayKey INT NOT NULL,
    SnapshotDateKey INT NOT NULL,
    EmploymentStatus NVARCHAR(100),
    EmployerName NVARCHAR(200),
    WageBand NVARCHAR(50),
    HoursPerWeekBand NVARCHAR(50)
);

-- FactRentCharge
CREATE TABLE dw.FactRentCharge (
    RentChargeKey INT IDENTITY(1,1) PRIMARY KEY,
    RentChargeID INT NOT NULL,
    StayKey INT NOT NULL,
    ChargeDateKey INT NOT NULL,
    Amount DECIMAL(10,2),
    WeekNumber INT
);

-- FactRentPayment
CREATE TABLE dw.FactRentPayment (
    RentPaymentKey INT IDENTITY(1,1) PRIMARY KEY,
    RentPaymentID INT NOT NULL,
    StayKey INT NOT NULL,
    PaymentDateKey INT NOT NULL,
    Amount DECIMAL(10,2),
    PaymentMethod NVARCHAR(50)
);

-- FactRentWaiver
CREATE TABLE dw.FactRentWaiver (
    RentWaiverKey INT IDENTITY(1,1) PRIMARY KEY,
    RentWaiverID INT NOT NULL,
    StayKey INT NOT NULL,
    WaiverDateKey INT NOT NULL,
    Amount DECIMAL(10,2),
    Reason NVARCHAR(200),
    ApprovedBy NVARCHAR(200)
);

-- FactFinancialAssistance
CREATE TABLE dw.FactFinancialAssistance (
    FinancialAssistanceKey INT IDENTITY(1,1) PRIMARY KEY,
    FinancialAssistanceID INT NOT NULL,
    StayKey INT NOT NULL,
    AssistanceDateKey INT NOT NULL,
    Amount DECIMAL(10,2),
    Source NVARCHAR(200),
    Notes NVARCHAR(500)
);

-- DimDonor
CREATE TABLE dw.DimDonor (
    DonorKey        INT IDENTITY(1,1) PRIMARY KEY,
    DonorID         INT NOT NULL,
    DonorType       NVARCHAR(50),
    OrganizationName NVARCHAR(200),
    FirstName       NVARCHAR(50),
    LastName        NVARCHAR(50),
    City            NVARCHAR(100),
    IsRecurring     BIT,
    IsAnonymous     BIT   -- TRUE when DonorType = 'Anonymous'
);

-- DimFundraisingEvent
-- Includes a sentinel row (EventID = 0) for general/unlinked donations
CREATE TABLE dw.DimFundraisingEvent (
    EventKey        INT IDENTITY(1,1) PRIMARY KEY,
    EventID         INT NOT NULL,
    EventName       NVARCHAR(150),
    EventType       NVARCHAR(50),
    EventDate       DATE,
    Goal            DECIMAL(12,2),
    IsGeneralFund   BIT   -- TRUE for the sentinel "General Fund" row
);

-- FactDonation
-- FundraisingEventID = 0 means general fund (no specific event)
CREATE TABLE dw.FactDonation (
    DonationKey        INT IDENTITY(1,1) PRIMARY KEY,
    DonationID         INT NOT NULL,
    DonorID            INT NOT NULL,
    FundraisingEventID INT NOT NULL,   -- 0 = General Fund
    DonationDateKey    INT NOT NULL,
    Amount             DECIMAL(10,2),
    PaymentMethod      NVARCHAR(50)
);

PRINT 'DW build complete.';