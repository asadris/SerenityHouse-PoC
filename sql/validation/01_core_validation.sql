/******************************************************************************************
 SET 1 � CORE INTEGRITY VALIDATION SUITE
 Serenity House Synthetic Data QA
 ------------------------------------------------------------------------------------------
 This script checks:
   � Overlapping stays (participant-level)
   � Overlapping stays (bed-level)
   � Invalid date logic
   � Missing required demographic fields
   � Missing lookup references
   � Orphaned foreign keys
   � Required fields in dependent tables
******************************************************************************************/

/******************************************************************************************
 1. OVERLAPPING STAYS FOR THE SAME PARTICIPANT
    Ensures no participant has two stays that overlap in time.
******************************************************************************************/
SELECT 
    s1.StayID AS Stay1,
    s2.StayID AS Stay2,
    s1.ResidentID,
    s1.IntakeDate AS Stay1Start,
    s1.ExitDate AS Stay1End,
    s2.IntakeDate AS Stay2Start,
    s2.ExitDate AS Stay2End
FROM sh.Stay s1
JOIN sh.Stay s2
    ON s1.ResidentID = s2.ResidentID
    AND s1.StayID < s2.StayID
    AND s1.IntakeDate <= s2.ExitDate
    AND s2.IntakeDate <= s1.ExitDate;


/******************************************************************************************
 2. OVERLAPPING STAYS FOR THE SAME BED
    Ensures no bed is assigned to two participants at the same time.
******************************************************************************************/
SELECT 
    s1.StayID AS Stay1,
    s2.StayID AS Stay2,
    s1.BedID,
    s1.IntakeDate AS Stay1Start,
    s1.ExitDate AS Stay1End,
    s2.IntakeDate AS Stay2Start,
    s2.ExitDate AS Stay2End
FROM sh.Stay s1
JOIN sh.Stay s2
    ON s1.BedID = s2.BedID
    AND s1.StayID < s2.StayID
    AND s1.IntakeDate <= s2.ExitDate
    AND s2.IntakeDate <= s1.ExitDate;


/******************************************************************************************
 3. INVALID DATE LOGIC
    Ensures no stay has an ExitDate earlier than IntakeDate.
******************************************************************************************/
SELECT StayID, ResidentID, IntakeDate, ExitDate
FROM sh.Stay
WHERE ExitDate < IntakeDate;


/******************************************************************************************
 4. PARTICIPANTS MISSING REQUIRED DEMOGRAPHIC FIELDS
    Ensures core identity fields are populated.
******************************************************************************************/
SELECT ResidentID, FirstName, LastName, DateOfBirth
FROM sh.Resident
WHERE FirstName IS NULL
   OR LastName IS NULL
   OR DateOfBirth IS NULL;


/******************************************************************************************
 5. STAYS REFERENCING MISSING CASE MANAGERS
    Ensures CaseManagerID always points to a valid CaseManager.
******************************************************************************************/
SELECT s.StayID, s.CaseManagerID
FROM sh.Stay s
LEFT JOIN sh.CaseManager cm ON s.CaseManagerID = cm.CaseManagerID
WHERE cm.CaseManagerID IS NULL;


/******************************************************************************************
 6. STAYS REFERENCING MISSING REFERRAL SOURCES
    Ensures ReferralSourceID is valid when present.
******************************************************************************************/
SELECT s.StayID, s.ReferralSourceID
FROM sh.Stay s
LEFT JOIN sh.ReferralSource r ON s.ReferralSourceID = r.ReferralSourceID
WHERE s.ReferralSourceID IS NOT NULL
  AND r.ReferralSourceID IS NULL;


/******************************************************************************************
 7. SERVICE ENCOUNTERS REFERENCING MISSING SERVICE TYPES
    Ensures ServiceTypeID always points to a valid ServiceType.
******************************************************************************************/
SELECT se.ServiceEncounterID, se.ServiceTypeID
FROM sh.ServiceEncounter se
LEFT JOIN sh.ServiceType st ON se.ServiceTypeID = st.ServiceTypeID
WHERE st.ServiceTypeID IS NULL;


/******************************************************************************************
 8. DRUG TESTS MISSING REQUIRED FIELDS
    Ensures TestDate, IsInitialTest, and Result are always populated.
******************************************************************************************/
SELECT DrugTestID, StayID, ResidentID, TestDate, IsInitialTest, Result
FROM sh.DrugTest
WHERE TestDate IS NULL
   OR IsInitialTest IS NULL
   OR Result IS NULL;


/******************************************************************************************
 9. OUTCOMES MISSING REQUIRED FIELDS
    Ensures IsSuccessfulExit is always populated.
******************************************************************************************/
SELECT OutcomeID, StayID, IsSuccessfulExit
FROM sh.Outcome
WHERE IsSuccessfulExit IS NULL;


/******************************************************************************************
 10. STAYS REFERENCING MISSING PARTICIPANTS
     Ensures ResidentID always points to a valid Resident.
******************************************************************************************/
SELECT s.StayID, s.ResidentID
FROM sh.Stay s
LEFT JOIN sh.Resident p ON s.ResidentID = p.ResidentID
WHERE p.ResidentID IS NULL;