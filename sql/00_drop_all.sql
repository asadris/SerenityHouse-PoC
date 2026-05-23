-- ============================================================
-- 00_drop_all.sql
-- Drops all sh and dw objects for a clean rebuild.
-- Run this BEFORE running the schema creation scripts.
-- Safe to run multiple times (checks existence before dropping).
-- ============================================================

-- -------------------------------------------------------
-- 1. Drop all foreign key constraints (sh schema)
-- -------------------------------------------------------
DECLARE @sql NVARCHAR(MAX) = '';

SELECT @sql += 'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))
             + '.' + QUOTENAME(OBJECT_NAME(parent_object_id))
             + ' DROP CONSTRAINT ' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.foreign_keys
WHERE OBJECT_SCHEMA_NAME(parent_object_id) IN ('sh', 'dw');

IF LEN(@sql) > 0
    EXEC sp_executesql @sql;

-- -------------------------------------------------------
-- 2. Drop dw tables (facts first, then dims)
-- -------------------------------------------------------
IF OBJECT_ID('dw.FactDonation',              'U') IS NOT NULL DROP TABLE dw.FactDonation;
IF OBJECT_ID('dw.FactFinancialAssistance',   'U') IS NOT NULL DROP TABLE dw.FactFinancialAssistance;
IF OBJECT_ID('dw.FactRentWaiver',            'U') IS NOT NULL DROP TABLE dw.FactRentWaiver;
IF OBJECT_ID('dw.FactRentPayment',           'U') IS NOT NULL DROP TABLE dw.FactRentPayment;
IF OBJECT_ID('dw.FactRentCharge',            'U') IS NOT NULL DROP TABLE dw.FactRentCharge;
IF OBJECT_ID('dw.FactEmploymentSnapshot',    'U') IS NOT NULL DROP TABLE dw.FactEmploymentSnapshot;
IF OBJECT_ID('dw.FactIncident',              'U') IS NOT NULL DROP TABLE dw.FactIncident;
IF OBJECT_ID('dw.FactDrugTest',              'U') IS NOT NULL DROP TABLE dw.FactDrugTest;
IF OBJECT_ID('dw.FactServiceEncounter',      'U') IS NOT NULL DROP TABLE dw.FactServiceEncounter;
IF OBJECT_ID('dw.FactStay',                  'U') IS NOT NULL DROP TABLE dw.FactStay;
IF OBJECT_ID('dw.DimDonor',                  'U') IS NOT NULL DROP TABLE dw.DimDonor;
IF OBJECT_ID('dw.DimFundraisingEvent',        'U') IS NOT NULL DROP TABLE dw.DimFundraisingEvent;
IF OBJECT_ID('dw.DimIncidentType',           'U') IS NOT NULL DROP TABLE dw.DimIncidentType;
IF OBJECT_ID('dw.DimServiceType',            'U') IS NOT NULL DROP TABLE dw.DimServiceType;
IF OBJECT_ID('dw.DimReferralSource',         'U') IS NOT NULL DROP TABLE dw.DimReferralSource;
IF OBJECT_ID('dw.DimCaseManager',            'U') IS NOT NULL DROP TABLE dw.DimCaseManager;
IF OBJECT_ID('dw.DimBed',                    'U') IS NOT NULL DROP TABLE dw.DimBed;
IF OBJECT_ID('dw.DimRoom',                   'U') IS NOT NULL DROP TABLE dw.DimRoom;
IF OBJECT_ID('dw.DimHouse',                  'U') IS NOT NULL DROP TABLE dw.DimHouse;
IF OBJECT_ID('dw.DimResident',               'U') IS NOT NULL DROP TABLE dw.DimResident;
IF OBJECT_ID('dw.DimDate',                   'U') IS NOT NULL DROP TABLE dw.DimDate;

-- -------------------------------------------------------
-- 3. Drop sh tables (children first, parents last)
-- -------------------------------------------------------
IF OBJECT_ID('sh.FundraisingDonation',       'U') IS NOT NULL DROP TABLE sh.FundraisingDonation;
IF OBJECT_ID('sh.FundraisingEvent',          'U') IS NOT NULL DROP TABLE sh.FundraisingEvent;
IF OBJECT_ID('sh.Donor',                     'U') IS NOT NULL DROP TABLE sh.Donor;
IF OBJECT_ID('sh.ProgramPayment',            'U') IS NOT NULL DROP TABLE sh.ProgramPayment;
IF OBJECT_ID('sh.FinancialAssistanceProgram','U') IS NOT NULL DROP TABLE sh.FinancialAssistanceProgram;
IF OBJECT_ID('sh.FinancialAssistance',       'U') IS NOT NULL DROP TABLE sh.FinancialAssistance;
IF OBJECT_ID('sh.RentWaiver',                'U') IS NOT NULL DROP TABLE sh.RentWaiver;
IF OBJECT_ID('sh.RentPayment',               'U') IS NOT NULL DROP TABLE sh.RentPayment;
IF OBJECT_ID('sh.RentCharge',                'U') IS NOT NULL DROP TABLE sh.RentCharge;
IF OBJECT_ID('sh.Outcome',                   'U') IS NOT NULL DROP TABLE sh.Outcome;
IF OBJECT_ID('sh.StayEmploymentSnapshot',    'U') IS NOT NULL DROP TABLE sh.StayEmploymentSnapshot;
IF OBJECT_ID('sh.Incident',                  'U') IS NOT NULL DROP TABLE sh.Incident;
IF OBJECT_ID('sh.DrugTest',                  'U') IS NOT NULL DROP TABLE sh.DrugTest;
IF OBJECT_ID('sh.ServiceEncounter',          'U') IS NOT NULL DROP TABLE sh.ServiceEncounter;
IF OBJECT_ID('sh.SecurityIdentityMap',       'U') IS NOT NULL DROP TABLE sh.SecurityIdentityMap;
IF OBJECT_ID('sh.Stay',                      'U') IS NOT NULL DROP TABLE sh.Stay;
IF OBJECT_ID('sh.ServiceType',               'U') IS NOT NULL DROP TABLE sh.ServiceType;
IF OBJECT_ID('sh.IncidentType',              'U') IS NOT NULL DROP TABLE sh.IncidentType;
IF OBJECT_ID('sh.Resident',                  'U') IS NOT NULL DROP TABLE sh.Resident;
IF OBJECT_ID('sh.Bed',                       'U') IS NOT NULL DROP TABLE sh.Bed;
IF OBJECT_ID('sh.Room',                      'U') IS NOT NULL DROP TABLE sh.Room;
IF OBJECT_ID('sh.House',                     'U') IS NOT NULL DROP TABLE sh.House;
IF OBJECT_ID('sh.ReferralSource',            'U') IS NOT NULL DROP TABLE sh.ReferralSource;
IF OBJECT_ID('sh.CaseManager',               'U') IS NOT NULL DROP TABLE sh.CaseManager;

-- -------------------------------------------------------
-- 4. Drop all stored procedures, views, and functions
--    in sh and dw schemas (must go before schema drop)
-- -------------------------------------------------------
DECLARE @sql2 NVARCHAR(MAX) = '';

SELECT @sql2 += 'DROP ' +
    CASE o.type
        WHEN 'P'  THEN 'PROCEDURE'
        WHEN 'V'  THEN 'VIEW'
        WHEN 'FN' THEN 'FUNCTION'
        WHEN 'TF' THEN 'FUNCTION'
        WHEN 'IF' THEN 'FUNCTION'
    END
    + ' ' + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) + ';' + CHAR(13)
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name IN ('sh', 'dw')
  AND o.type IN ('P', 'V', 'FN', 'TF', 'IF');

IF LEN(@sql2) > 0
    EXEC sp_executesql @sql2;

-- -------------------------------------------------------
-- 5. Drop schemas (only if now empty)
-- -------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dw')
    DROP SCHEMA dw;

IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sh')
    DROP SCHEMA sh;

-- -------------------------------------------------------
-- 6. Confirm
-- -------------------------------------------------------
SELECT
    'sh tables remaining' AS Check_, COUNT(*) AS Count
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'sh'
UNION ALL
SELECT
    'dw tables remaining', COUNT(*)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'dw';
