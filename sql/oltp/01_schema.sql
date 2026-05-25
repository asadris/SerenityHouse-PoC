-- =============================================================================
-- Serenity House PoC — OLTP Schema (v6)
-- Schema: sh (Serenity House)
-- Target:  SQL Server (PETRISLAP2025\PETRIS2022, database Serenity1)
-- Created: 2026-05-20
-- Notes:
--   • Drop/create approach for development — wrap in transaction
--   • All foreign keys defined at end for clean creation order
--   • Behavioral clusters are NOT stored — inferred at query time from
--     PaymentRatio: Reliable ≥0.85, Struggling 0.40–0.84, Chronic <0.40
--   • Identity masking via SecurityIdentityMap (UUID ↔ ResidentID)
--   • Meeting compliance tracked as incidents (not a separate table)
--   • Case notes stored as NoteText/NoteDate on Stay (simplified for PoC)
-- =============================================================================

USE Serenity1;

-- =============================================================================
-- SECTION 0 — Drop all objects (safe dev reset)
-- =============================================================================

-- Drop foreign keys first (order matters)
IF OBJECT_ID('sh.ProgramPayment',            'U') IS NOT NULL DROP TABLE sh.ProgramPayment;
IF OBJECT_ID('sh.FinancialAssistanceProgram','U') IS NOT NULL DROP TABLE sh.FinancialAssistanceProgram;
IF OBJECT_ID('sh.RentWaiver',                'U') IS NOT NULL DROP TABLE sh.RentWaiver;
IF OBJECT_ID('sh.RentPayment',               'U') IS NOT NULL DROP TABLE sh.RentPayment;
IF OBJECT_ID('sh.RentCharge',                'U') IS NOT NULL DROP TABLE sh.RentCharge;
IF OBJECT_ID('sh.FundraisingDonation',       'U') IS NOT NULL DROP TABLE sh.FundraisingDonation;
IF OBJECT_ID('sh.FundraisingEvent',          'U') IS NOT NULL DROP TABLE sh.FundraisingEvent;
IF OBJECT_ID('sh.Donor',                     'U') IS NOT NULL DROP TABLE sh.Donor;
IF OBJECT_ID('sh.Outcome',                   'U') IS NOT NULL DROP TABLE sh.Outcome;
IF OBJECT_ID('sh.StayEmploymentSnapshot',    'U') IS NOT NULL DROP TABLE sh.StayEmploymentSnapshot;
IF OBJECT_ID('sh.Incident',                  'U') IS NOT NULL DROP TABLE sh.Incident;
IF OBJECT_ID('sh.IncidentType',              'U') IS NOT NULL DROP TABLE sh.IncidentType;
IF OBJECT_ID('sh.DrugTest',                  'U') IS NOT NULL DROP TABLE sh.DrugTest;
IF OBJECT_ID('sh.ServiceEncounter',          'U') IS NOT NULL DROP TABLE sh.ServiceEncounter;
IF OBJECT_ID('sh.ServiceType',               'U') IS NOT NULL DROP TABLE sh.ServiceType;
IF OBJECT_ID('sh.SecurityIdentityMap',       'U') IS NOT NULL DROP TABLE sh.SecurityIdentityMap;
IF OBJECT_ID('sh.Stay',                      'U') IS NOT NULL DROP TABLE sh.Stay;
IF OBJECT_ID('sh.CaseManager',               'U') IS NOT NULL DROP TABLE sh.CaseManager;
IF OBJECT_ID('sh.ReferralSource',            'U') IS NOT NULL DROP TABLE sh.ReferralSource;
IF OBJECT_ID('sh.Resident',               'U') IS NOT NULL DROP TABLE sh.Resident;
IF OBJECT_ID('sh.Bed',                       'U') IS NOT NULL DROP TABLE sh.Bed;
IF OBJECT_ID('sh.Room',                      'U') IS NOT NULL DROP TABLE sh.Room;
IF OBJECT_ID('sh.House',                     'U') IS NOT NULL DROP TABLE sh.House;

-- Create schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sh')
    EXEC('CREATE SCHEMA sh');


-- =============================================================================
-- SECTION 1 — Housing (House → Room → Bed)
-- =============================================================================

CREATE TABLE sh.House (
    HouseID          INT            IDENTITY(1,1) PRIMARY KEY,
    HouseName        NVARCHAR(100)  NOT NULL,
    Address          NVARCHAR(200)  NULL,
    City             NVARCHAR(100)  NULL,
    StateCode        CHAR(2)        NULL,
    ZipCode          VARCHAR(10)    NULL,
    TotalBeds        INT            NOT NULL DEFAULT 45,
    IsActive         BIT            NOT NULL DEFAULT 1,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE sh.Room (
    RoomID           INT            IDENTITY(1,1) PRIMARY KEY,
    HouseID          INT            NOT NULL,
    RoomNumber       VARCHAR(10)    NOT NULL,   -- e.g. '101', '202'
    RoomType         NVARCHAR(50)   NULL,        -- e.g. 'Standard', 'Accessible'
    BedsInRoom       INT            NOT NULL DEFAULT 3,
    IsActive         BIT            NOT NULL DEFAULT 1,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Room_HouseRoom UNIQUE (HouseID, RoomNumber)
);

CREATE TABLE sh.Bed (
    BedID            INT            IDENTITY(1,1) PRIMARY KEY,
    RoomID           INT            NOT NULL,
    BedLabel         VARCHAR(10)    NOT NULL,   -- 'A', 'B', 'C'
    IsActive         BIT            NOT NULL DEFAULT 1,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Bed_RoomLabel UNIQUE (RoomID, BedLabel)
);


-- =============================================================================
-- SECTION 2 — People (Resident, CaseManager, ReferralSource)
-- =============================================================================

CREATE TABLE sh.ReferralSource (
    ReferralSourceID   INT            IDENTITY(1,1) PRIMARY KEY,
    SourceName         NVARCHAR(100)  NOT NULL,
    SourceCategory     NVARCHAR(50)   NULL   -- 'Court', 'Treatment', 'Self', 'Family', 'Other'
);

CREATE TABLE sh.CaseManager (
    CaseManagerID    INT            IDENTITY(1,1) PRIMARY KEY,
    FirstName        NVARCHAR(50)   NOT NULL,
    LastName         NVARCHAR(50)   NOT NULL,
    Email            NVARCHAR(150)  NULL,
    Phone            VARCHAR(20)    NULL,
    IsActive         BIT            NOT NULL DEFAULT 1,
    HiredDate        DATE           NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE sh.Resident (
    ResidentID          INT            IDENTITY(1,1) PRIMARY KEY,

    -- Demographics
    FirstName              NVARCHAR(50)   NOT NULL,
    LastName               NVARCHAR(50)   NOT NULL,
    DateOfBirth            DATE           NOT NULL,
    Gender                 NVARCHAR(20)   NULL,   -- 'Male','Female','Non-binary','Other'
    Race                   NVARCHAR(50)   NULL,
    Ethnicity              NVARCHAR(50)   NULL,
    MaritalStatus          NVARCHAR(30)   NULL,
    EducationLevel         NVARCHAR(50)   NULL,

    -- Contact
    Phone                  VARCHAR(20)    NULL,
    Email                  NVARCHAR(150)  NULL,
    HomeCity               NVARCHAR(100)  NULL,
    HomeState              CHAR(2)        NULL,

    -- Origin / referral geography (where the resident came from — "Areas Served")
    OriginCity             NVARCHAR(100)  NULL,
    OriginState            CHAR(2)        NULL,
    OriginCounty           NVARCHAR(100)  NULL,

    -- Emergency contact
    EmergencyContactName   NVARCHAR(100)  NULL,
    EmergencyContactPhone  VARCHAR(20)    NULL,
    EmergencyContactRel    NVARCHAR(50)   NULL,   -- 'Mother','Spouse', etc.

    -- Program identifiers
    NationalID             VARCHAR(30)    NULL,   -- masked / anonymized
    AlternateID            VARCHAR(30)    NULL,   -- court ID, referral ID, etc.

    -- Recovery background
    PrimarySubstance       NVARCHAR(50)   NULL,
    SubstanceUseStartAge   INT            NULL,
    PriorTreatmentCount    INT            NOT NULL DEFAULT 0,

    CreatedAt              DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

-- UUID-based identity masking: never expose ResidentID externally
CREATE TABLE sh.SecurityIdentityMap (
    MapID                  INT            IDENTITY(1,1) PRIMARY KEY,
    ResidentID          INT            NOT NULL,
    PublicResidentID    UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    CreatedAt              DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_SecurityMap_Resident UNIQUE (ResidentID),
    CONSTRAINT UQ_SecurityMap_Public     UNIQUE (PublicResidentID)
);


-- =============================================================================
-- SECTION 3 — Stays
-- =============================================================================

CREATE TABLE sh.Stay (
    StayID             INT            IDENTITY(1,1) PRIMARY KEY,
    ResidentID      INT            NOT NULL,
    BedID              INT            NOT NULL,   -- primary bed assignment
    CaseManagerID      INT            NOT NULL,
    ReferralSourceID   INT            NULL,

    -- Dates
    IntakeDate         DATE           NOT NULL,
    ExitDate           DATE           NULL,       -- NULL = currently active

    -- Status
    --   Active       = currently residing
    --   Completed    = successfully completed program
    --   Terminated   = removed / left AMA
    --   Transferred  = moved to another facility
    StayStatus         NVARCHAR(20)   NOT NULL DEFAULT 'Active'
                           CONSTRAINT CK_Stay_Status CHECK (
                               StayStatus IN ('Active','Completed','Terminated','Transferred')),

    ExitReason         NVARCHAR(200)  NULL,       -- free text exit reason

    -- Case notes (simplified PoC — one note block per stay)
    -- For a production system, replace with a CaseNotes child table
    NoteText           NVARCHAR(MAX)  NULL,
    NoteDate           DATE           NULL,

    -- Program compliance flags (computed upstream; stored for reporting)
    MeetingRequirement NVARCHAR(20)   NULL DEFAULT 'Phase1'
                           CONSTRAINT CK_Stay_MeetingReq CHECK (
                               MeetingRequirement IN ('Phase1','Phase2') OR MeetingRequirement IS NULL),
    -- Phase1: first 90 days — 1 AA/NA meeting per day required
    -- Phase2: after 90 days  — minimum 4 meetings per week

    CreatedAt          DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Index for common filters
CREATE INDEX IX_Stay_Resident  ON sh.Stay (ResidentID);
CREATE INDEX IX_Stay_IntakeDate   ON sh.Stay (IntakeDate);
CREATE INDEX IX_Stay_ExitDate     ON sh.Stay (ExitDate);
CREATE INDEX IX_Stay_Status       ON sh.Stay (StayStatus);


-- =============================================================================
-- SECTION 4 — Services & Compliance
-- =============================================================================

CREATE TABLE sh.ServiceType (
    ServiceTypeID    INT            IDENTITY(1,1) PRIMARY KEY,
    ServiceName      NVARCHAR(100)  NOT NULL,
    IsRequired       BIT            NOT NULL DEFAULT 0,  -- mandatory vs optional
    Description      NVARCHAR(300)  NULL
);

-- Tracks attendance at each service event per stay
CREATE TABLE sh.ServiceEncounter (
    EncounterID      INT            IDENTITY(1,1) PRIMARY KEY,
    StayID           INT            NOT NULL,
    ServiceTypeID    INT            NOT NULL,
    EncounterDate    DATE           NOT NULL,
    Attended         BIT            NOT NULL DEFAULT 1,
    Notes            NVARCHAR(500)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_ServiceEnc_Stay ON sh.ServiceEncounter (StayID);
CREATE INDEX IX_ServiceEnc_Date ON sh.ServiceEncounter (EncounterDate);


-- =============================================================================
-- SECTION 5 — Drug Testing
-- =============================================================================

CREATE TABLE sh.DrugTest (
    DrugTestID         INT            IDENTITY(1,1) PRIMARY KEY,
    StayID             INT            NOT NULL,
    TestDate           DATE           NOT NULL,
    TestType           NVARCHAR(50)   NOT NULL DEFAULT 'Urine',  -- 'Urine','Breathalyzer','Hair'
    Result             NVARCHAR(20)   NOT NULL
                           CONSTRAINT CK_DrugTest_Result CHECK (Result IN ('Negative','Positive','Refused','Inconclusive')),
    SubstancesDetected NVARCHAR(200)  NULL,   -- comma-separated if positive
    AdministeredBy     NVARCHAR(100)  NULL,
    IsRandom           BIT            NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_DrugTest_Stay ON sh.DrugTest (StayID);
CREATE INDEX IX_DrugTest_Date ON sh.DrugTest (TestDate);


-- =============================================================================
-- SECTION 6 — Incidents & Disciplinary
-- =============================================================================

-- Incident types include meeting non-compliance, curfew violations, etc.
CREATE TABLE sh.IncidentType (
    IncidentTypeID   INT            IDENTITY(1,1) PRIMARY KEY,
    TypeName         NVARCHAR(100)  NOT NULL,
    Severity         NVARCHAR(20)   NOT NULL DEFAULT 'Low'
                         CONSTRAINT CK_IncidentType_Severity CHECK (Severity IN ('Low','Medium','High','Critical')),
    Description      NVARCHAR(300)  NULL
    -- Example types:
    --   'Curfew Violation'         (Low/Medium)
    --   'Meeting Non-Compliance'   (Low/Medium)
    --   'Chore Non-Compliance'     (Low)
    --   'Positive Drug Test'       (High)
    --   'Alcohol Use'              (High)
    --   'Physical Altercation'     (Critical)
    --   'Property Damage'          (Medium)
    --   'Unauthorized Guest'       (Medium)
    --   'Employment Non-Compliance'(Medium)  -- failure to seek/maintain job within 15 days
    --   'House Meeting Absence'    (Low)
);

CREATE TABLE sh.Incident (
    IncidentID         INT            IDENTITY(1,1) PRIMARY KEY,
    StayID             INT            NOT NULL,
    IncidentTypeID     INT            NOT NULL,
    IncidentDate       DATE           NOT NULL,
    Description        NVARCHAR(500)  NULL,
    ActionTaken        NVARCHAR(300)  NULL,  -- 'Warning','Probation','Discharge', etc.
    FollowUpRequired   BIT            NOT NULL DEFAULT 0,
    FollowUpDate       DATE           NULL,
    FollowUpNotes      NVARCHAR(500)  NULL,
    ReportedBy         NVARCHAR(100)  NULL,
    CreatedAt          DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_Incident_Stay ON sh.Incident (StayID);
CREATE INDEX IX_Incident_Date ON sh.Incident (IncidentDate);


-- =============================================================================
-- SECTION 7 — Employment
-- =============================================================================

-- Periodic snapshots of employment status during stay.
-- Rule: full-time employment (≥40 hrs/week) required within 15 days of intake.
-- Non-compliance tracked as an incident (IncidentType: 'Employment Non-Compliance').
CREATE TABLE sh.StayEmploymentSnapshot (
    SnapshotID       INT             IDENTITY(1,1) PRIMARY KEY,
    StayID           INT             NOT NULL,
    SnapshotDate     DATE            NOT NULL,
    EmploymentStatus NVARCHAR(30)    NOT NULL
                         CONSTRAINT CK_EmpSnap_Status CHECK (
                             EmploymentStatus IN ('Unemployed','Part-Time','Full-Time','Self-Employed','Disabled','Retired')),
    Employer         NVARCHAR(150)   NULL,
    JobTitle         NVARCHAR(100)   NULL,
    HourlyWage       DECIMAL(8,2)    NULL,   -- actual wage (not a band)
    HoursPerWeek     INT             NULL,   -- actual hours (not a band)
    StartDate        DATE            NULL,   -- start of this job
    EndDate          DATE            NULL,   -- NULL = still employed at this job
    CreatedAt        DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_EmpSnap_Stay ON sh.StayEmploymentSnapshot (StayID);


-- =============================================================================
-- SECTION 8 — Outcomes
-- =============================================================================

-- Multiple outcomes can be recorded per stay (housing destination, sobriety, etc.)
CREATE TABLE sh.Outcome (
    OutcomeID        INT            IDENTITY(1,1) PRIMARY KEY,
    StayID           INT            NOT NULL,
    OutcomeDate      DATE           NOT NULL,
    OutcomeType      NVARCHAR(100)  NOT NULL,
    -- Example types: 'Exit Destination','Sobriety Length','Employment at Exit',
    --                'Housing Secured','Program Completion','Relapse'
    OutcomeValue     NVARCHAR(200)  NOT NULL,
    Notes            NVARCHAR(500)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_Outcome_Stay ON sh.Outcome (StayID);


-- =============================================================================
-- SECTION 9 — Financial (Rent)
-- =============================================================================

-- Weekly rent charges generated per stay
CREATE TABLE sh.RentCharge (
    ChargeID         INT            IDENTITY(1,1) PRIMARY KEY,
    StayID           INT            NOT NULL,
    ChargeDate       DATE           NOT NULL,
    AmountCharged    DECIMAL(10,2)  NOT NULL,
    Description      NVARCHAR(200)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_RentCharge_Stay ON sh.RentCharge (StayID);
CREATE INDEX IX_RentCharge_Date ON sh.RentCharge (ChargeDate);

-- Payments made against charges
CREATE TABLE sh.RentPayment (
    PaymentID        INT            IDENTITY(1,1) PRIMARY KEY,
    StayID           INT            NOT NULL,
    PaymentDate      DATE           NOT NULL,
    AmountPaid       DECIMAL(10,2)  NOT NULL,
    PaymentMethod    NVARCHAR(50)   NULL,  -- 'Cash','Check','EFT','Money Order'
    Notes            NVARCHAR(200)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_RentPayment_Stay ON sh.RentPayment (StayID);

-- Waivers/forgiveness of specific charge amounts
CREATE TABLE sh.RentWaiver (
    WaiverID         INT            IDENTITY(1,1) PRIMARY KEY,
    StayID           INT            NOT NULL,
    ChargeID         INT            NULL,   -- optional: link to specific charge
    WaiverDate       DATE           NOT NULL,
    AmountWaived     DECIMAL(10,2)  NOT NULL,
    WaiverReason     NVARCHAR(200)  NULL,
    ApprovedBy       NVARCHAR(100)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_RentWaiver_Stay ON sh.RentWaiver (StayID);

-- Third-party financial assistance programs (Section 8, VASH, county programs, etc.)
CREATE TABLE sh.FinancialAssistanceProgram (
    ProgramID        INT            IDENTITY(1,1) PRIMARY KEY,
    ProgramName      NVARCHAR(150)  NOT NULL,
    ProgramType      NVARCHAR(100)  NULL,  -- 'Federal','State','County','Nonprofit'
    Description      NVARCHAR(300)  NULL,
    IsActive         BIT            NOT NULL DEFAULT 1
);

-- Payments made by a third-party program on behalf of a stay
CREATE TABLE sh.ProgramPayment (
    ProgramPaymentID INT            IDENTITY(1,1) PRIMARY KEY,
    StayID           INT            NOT NULL,
    ProgramID        INT            NOT NULL,
    PaymentDate      DATE           NOT NULL,
    AmountPaid       DECIMAL(10,2)  NOT NULL,
    ReferenceNumber  VARCHAR(50)    NULL,
    Notes            NVARCHAR(200)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_ProgramPayment_Stay    ON sh.ProgramPayment (StayID);
CREATE INDEX IX_ProgramPayment_Program ON sh.ProgramPayment (ProgramID);


-- =============================================================================
-- SECTION 10 — Fundraising
-- =============================================================================

CREATE TABLE sh.Donor (
    DonorID          INT            IDENTITY(1,1) PRIMARY KEY,
    DonorType        NVARCHAR(30)   NOT NULL DEFAULT 'Individual'
                         CONSTRAINT CK_Donor_Type CHECK (
                             DonorType IN ('Individual','Business','Church','Foundation','Anonymous')),
    OrganizationName NVARCHAR(200)  NULL,   -- for non-individual donors
    FirstName        NVARCHAR(50)   NULL,
    LastName         NVARCHAR(50)   NULL,
    Email            NVARCHAR(150)  NULL,
    Phone            VARCHAR(20)    NULL,
    City             NVARCHAR(100)  NULL,
    StateCode        CHAR(2)        NULL,
    IsRecurring      BIT            NOT NULL DEFAULT 0,
    FirstDonationDate DATE          NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE sh.FundraisingEvent (
    EventID          INT            IDENTITY(1,1) PRIMARY KEY,
    EventName        NVARCHAR(150)  NOT NULL,
    EventType        NVARCHAR(50)   NULL,   -- 'Gala','Golf Tournament','Online Drive','Walk'
    EventDate        DATE           NOT NULL,
    Goal             DECIMAL(12,2)  NULL,
    ActualRevenue    DECIMAL(12,2)  NULL,   -- updated after event
    ExpenseAmount    DECIMAL(12,2)  NULL,
    Location         NVARCHAR(200)  NULL,
    Description      NVARCHAR(500)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE sh.FundraisingDonation (
    DonationID       INT            IDENTITY(1,1) PRIMARY KEY,
    DonorID          INT            NOT NULL,
    EventID          INT            NULL,   -- NULL = general / unsolicited donation
    DonationDate     DATE           NOT NULL,
    Amount           DECIMAL(12,2)  NOT NULL,
    DonationType     NVARCHAR(50)   NULL,   -- 'Cash','Check','Credit Card','In-Kind','Stock'
    IsAnonymous      BIT            NOT NULL DEFAULT 0,
    Campaign         NVARCHAR(100)  NULL,
    Notes            NVARCHAR(300)  NULL,
    CreatedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_FundDonation_Donor ON sh.FundraisingDonation (DonorID);
CREATE INDEX IX_FundDonation_Event ON sh.FundraisingDonation (EventID);
CREATE INDEX IX_FundDonation_Date  ON sh.FundraisingDonation (DonationDate);


-- =============================================================================
-- SECTION 11 — Foreign Key Constraints
-- =============================================================================

-- Housing chain
ALTER TABLE sh.Room ADD CONSTRAINT FK_Room_House
    FOREIGN KEY (HouseID) REFERENCES sh.House (HouseID);

ALTER TABLE sh.Bed ADD CONSTRAINT FK_Bed_Room
    FOREIGN KEY (RoomID) REFERENCES sh.Room (RoomID);

-- Stay references
ALTER TABLE sh.Stay ADD CONSTRAINT FK_Stay_Resident
    FOREIGN KEY (ResidentID) REFERENCES sh.Resident (ResidentID);

ALTER TABLE sh.Stay ADD CONSTRAINT FK_Stay_Bed
    FOREIGN KEY (BedID) REFERENCES sh.Bed (BedID);

ALTER TABLE sh.Stay ADD CONSTRAINT FK_Stay_CaseManager
    FOREIGN KEY (CaseManagerID) REFERENCES sh.CaseManager (CaseManagerID);

ALTER TABLE sh.Stay ADD CONSTRAINT FK_Stay_ReferralSource
    FOREIGN KEY (ReferralSourceID) REFERENCES sh.ReferralSource (ReferralSourceID);

-- Identity map
ALTER TABLE sh.SecurityIdentityMap ADD CONSTRAINT FK_SecMap_Resident
    FOREIGN KEY (ResidentID) REFERENCES sh.Resident (ResidentID);

-- Services
ALTER TABLE sh.ServiceEncounter ADD CONSTRAINT FK_ServEnc_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

ALTER TABLE sh.ServiceEncounter ADD CONSTRAINT FK_ServEnc_ServiceType
    FOREIGN KEY (ServiceTypeID) REFERENCES sh.ServiceType (ServiceTypeID);

-- Drug tests
ALTER TABLE sh.DrugTest ADD CONSTRAINT FK_DrugTest_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

-- Incidents
ALTER TABLE sh.Incident ADD CONSTRAINT FK_Incident_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

ALTER TABLE sh.Incident ADD CONSTRAINT FK_Incident_Type
    FOREIGN KEY (IncidentTypeID) REFERENCES sh.IncidentType (IncidentTypeID);

-- Employment
ALTER TABLE sh.StayEmploymentSnapshot ADD CONSTRAINT FK_EmpSnap_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

-- Outcomes
ALTER TABLE sh.Outcome ADD CONSTRAINT FK_Outcome_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

-- Financial — rent
ALTER TABLE sh.RentCharge ADD CONSTRAINT FK_RentCharge_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

ALTER TABLE sh.RentPayment ADD CONSTRAINT FK_RentPayment_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

ALTER TABLE sh.RentWaiver ADD CONSTRAINT FK_RentWaiver_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

ALTER TABLE sh.RentWaiver ADD CONSTRAINT FK_RentWaiver_Charge
    FOREIGN KEY (ChargeID) REFERENCES sh.RentCharge (ChargeID);

ALTER TABLE sh.ProgramPayment ADD CONSTRAINT FK_ProgPayment_Stay
    FOREIGN KEY (StayID) REFERENCES sh.Stay (StayID);

ALTER TABLE sh.ProgramPayment ADD CONSTRAINT FK_ProgPayment_Program
    FOREIGN KEY (ProgramID) REFERENCES sh.FinancialAssistanceProgram (ProgramID);

-- Fundraising
ALTER TABLE sh.FundraisingDonation ADD CONSTRAINT FK_Donation_Donor
    FOREIGN KEY (DonorID) REFERENCES sh.Donor (DonorID);

ALTER TABLE sh.FundraisingDonation ADD CONSTRAINT FK_Donation_Event
    FOREIGN KEY (EventID) REFERENCES sh.FundraisingEvent (EventID);



-- =============================================================================
-- SECTION 12 — Seed / Lookup Data
-- =============================================================================

-- Referral Sources
INSERT INTO sh.ReferralSource (SourceName, SourceCategory) VALUES
-- Court / Criminal Justice
('Jail',                     'Court'),
('Prison',                   'Court'),
('Drug Court',               'Court'),
('Probation / Parole',       'Court'),
-- Local Treatment Centers (Clark County / Louisville area)
('Avenues',                  'Treatment'),
('Sunrise',                  'Treatment'),
('Hickory',                  'Treatment'),
('Centerstone',              'Treatment'),
('True Healing',             'Treatment'),
('Life Springs',             'Treatment'),
('Hospital',                 'Treatment'),
-- Self / Social
('Street',                   'Self'),
('Self-Referral',            'Self'),
('Family / Friend',          'Family'),
-- Other
('Other',                    'Other');

-- Service Types (mandatory and optional programming)
INSERT INTO sh.ServiceType (ServiceName, IsRequired, Description) VALUES
('AA/NA Meeting',            1, 'Alcoholics/Narcotics Anonymous — Phase 1: daily, Phase 2: 4+/week'),
('House Meeting',            1, 'Weekly mandatory all-resident house meeting'),
('Individual Counseling',    0, 'One-on-one counseling session with case manager or therapist'),
('Group Therapy',            1, 'Structured group therapy session'),
('Life Skills Workshop',     0, 'Budgeting, job readiness, and independent living skills'),
('Employment Workshop',      0, 'Resume building and job search support'),
('Community Service',        0, 'Voluntary community service activity'),
('Faith-Based Program',      0, 'Optional faith or spiritual programming'),
('Chore Rotation',           1, 'Assigned house chore completion'),
('Curfew Check-In',          1, 'Mandatory nightly curfew check-in');

-- Incident Types
INSERT INTO sh.IncidentType (TypeName, Severity, Description) VALUES
('Curfew Violation',          'Medium',   'Resident returned after curfew without approved exception'),
('Meeting Non-Compliance',    'Low',      'Missed required AA/NA or house meeting'),
('Positive Drug Test',        'High',     'Drug test returned positive result'),
('Positive Alcohol Test',     'High',     'Breathalyzer or test returned positive for alcohol'),
('Test Refusal',              'High',     'Resident refused mandatory drug/alcohol test'),
('Unauthorized Guest',        'Medium',   'Non-approved visitor in residence'),
('Physical Altercation',      'Critical', 'Physical fight or assault involving resident'),
('Property Damage',           'Medium',   'Damage to house property'),
('Chore Non-Compliance',      'Low',      'Failure to complete assigned chores'),
('Employment Non-Compliance', 'Medium',   'Failure to obtain or maintain employment within required timeframe'),
('House Meeting Absence',     'Low',      'Absent from mandatory house meeting without excuse'),
('Disruptive Behavior',       'Medium',   'Noise, disrespect, or disruptive conduct'),
('Theft',                     'Critical', 'Theft of property from residence or another resident'),
('Weapons Possession',        'Critical', 'Possession of prohibited weapons on premises'),
('Other',                     'Low',      'Other incident not covered by existing types');

-- Financial Assistance Programs
INSERT INTO sh.FinancialAssistanceProgram (ProgramName, ProgramType, Description) VALUES
('HUD Emergency Solutions Grant',    'Federal',   'Emergency housing assistance for homeless individuals'),
('Veterans Affairs VASH',            'Federal',   'HUD-VASH vouchers for veteran residents'),
('Recovery Works',                   'State',     'Indiana program helping residents in recovery with employment-related expenses'),
('County Housing Assistance',        'County',    'County-funded transitional housing support'),
('State Recovery Housing Fund',      'State',     'State grant program for recovery residences'),
('Salvation Army Assistance',        'Nonprofit', 'Faith-based emergency housing aid'),
('General Charity Fund',             'Nonprofit', 'Internal discretionary fund for approved waivers');


PRINT 'Serenity House OLTP schema (v6) created successfully.';
