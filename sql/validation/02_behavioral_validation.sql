/******************************************************************************************
 SET 2 � BEHAVIORAL VALIDATION SUITE
 Serenity House Synthetic Data QA
 ------------------------------------------------------------------------------------------
 This script checks:
   � Attendance realism by cluster
   � Drug test positivity rates by cluster
   � Incident frequency by cluster
   � Employment stability by cluster
   � Stay length distribution by cluster
   � Service encounter completeness
******************************************************************************************/

/******************************************************************************************
 1. ATTENDANCE PATTERNS BY CLUSTER
    Reliable participants should have high attendance and low no-shows.
    Chronic participants should have low attendance and high no-shows.
******************************************************************************************/
SELECT 
    p.ResidentID,
    p.FirstName,
    p.LastName,
    c.Cluster,
    COUNT(*) AS TotalEncounters,
    SUM(CASE WHEN se.AttendanceStatus = 'Present' THEN 1 ELSE 0 END) AS PresentCount,
    SUM(CASE WHEN se.AttendanceStatus = 'No-Show' THEN 1 ELSE 0 END) AS NoShowCount
FROM sh.Resident p
JOIN (
    -- cluster assignments stored in SecurityIdentityMap Notes? No.
    -- Instead, infer cluster from Stay patterns (generator stored cluster in memory only)
    -- We approximate cluster by behavior:
    SELECT 
        s.ResidentID,
        CASE 
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) > 300 THEN 'Chronic'
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) BETWEEN 120 AND 300 THEN 'Struggling'
            ELSE 'Reliable'
        END AS Cluster
    FROM sh.Stay s
    GROUP BY s.ResidentID
) c ON p.ResidentID = c.ResidentID
JOIN sh.Stay st ON st.ResidentID = p.ResidentID
JOIN sh.ServiceEncounter se ON se.StayID = st.StayID
GROUP BY p.ResidentID, p.FirstName, p.LastName, c.Cluster
HAVING 
    -- Flag suspicious patterns:
    (c.Cluster = 'Reliable' AND SUM(CASE WHEN se.AttendanceStatus = 'No-Show' THEN 1 END) > 5)
 OR (c.Cluster = 'Chronic' AND SUM(CASE WHEN se.AttendanceStatus = 'Present' THEN 1 END) > 10);


/******************************************************************************************
 2. DRUG TEST POSITIVITY RATES BY CLUSTER
    Reliable: ~5%
    Struggling: ~20%
    Chronic: ~40%
******************************************************************************************/
SELECT 
    p.ResidentID,
    p.FirstName,
    p.LastName,
    c.Cluster,
    COUNT(*) AS TotalTests,
    SUM(CASE WHEN dt.Result = 'Positive' THEN 1 ELSE 0 END) AS PositiveTests,
    CAST(SUM(CASE WHEN dt.Result = 'Positive' THEN 1 ELSE 0 END) * 1.0 
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2)) AS PositivityRate
FROM sh.Resident p
JOIN (
    SELECT 
        s.ResidentID,
        CASE 
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) > 300 THEN 'Chronic'
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) BETWEEN 120 AND 300 THEN 'Struggling'
            ELSE 'Reliable'
        END AS Cluster
    FROM sh.Stay s
    GROUP BY s.ResidentID
) c ON p.ResidentID = c.ResidentID
JOIN sh.Stay st ON st.ResidentID = p.ResidentID
JOIN sh.DrugTest dt ON dt.StayID = st.StayID
GROUP BY p.ResidentID, p.FirstName, p.LastName, c.Cluster
HAVING 
    (c.Cluster = 'Reliable' AND CAST(SUM(CASE WHEN dt.Result = 'Positive' THEN 1 END) * 1.0 
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2)) > 0.20)
 OR (c.Cluster = 'Chronic' AND CAST(SUM(CASE WHEN dt.Result = 'Positive' THEN 1 END) * 1.0 
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2)) < 0.10);


/******************************************************************************************
 3. INCIDENT FREQUENCY BY CLUSTER
    Reliable: 0�1 incidents
    Struggling: 0�3 incidents
    Chronic: 1�6 incidents
******************************************************************************************/
SELECT 
    p.ResidentID,
    p.FirstName,
    p.LastName,
    c.Cluster,
    COUNT(i.IncidentID) AS IncidentCount
FROM sh.Resident p
JOIN (
    SELECT 
        s.ResidentID,
        CASE 
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) > 300 THEN 'Chronic'
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) BETWEEN 120 AND 300 THEN 'Struggling'
            ELSE 'Reliable'
        END AS Cluster
    FROM sh.Stay s
    GROUP BY s.ResidentID
) c ON p.ResidentID = c.ResidentID
LEFT JOIN sh.Stay st ON st.ResidentID = p.ResidentID
LEFT JOIN sh.Incident i ON i.StayID = st.StayID
GROUP BY p.ResidentID, p.FirstName, p.LastName, c.Cluster
HAVING 
    (c.Cluster = 'Reliable' AND COUNT(i.IncidentID) > 2)
 OR (c.Cluster = 'Struggling' AND COUNT(i.IncidentID) > 5)
 OR (c.Cluster = 'Chronic' AND COUNT(i.IncidentID) < 1);


/******************************************************************************************
 4. EMPLOYMENT STABILITY BY CLUSTER
    Reliable: mostly employed
    Struggling: mixed
    Chronic: mostly unemployed
******************************************************************************************/
SELECT 
    p.ResidentID,
    p.FirstName,
    p.LastName,
    c.Cluster,
    SUM(CASE WHEN es.EmploymentStatus LIKE 'Employed%' THEN 1 ELSE 0 END) AS EmployedCount,
    SUM(CASE WHEN es.EmploymentStatus = 'Unemployed' THEN 1 ELSE 0 END) AS UnemployedCount
FROM sh.Resident p
JOIN (
    SELECT 
        s.ResidentID,
        CASE 
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) > 300 THEN 'Chronic'
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) BETWEEN 120 AND 300 THEN 'Struggling'
            ELSE 'Reliable'
        END AS Cluster
    FROM sh.Stay s
    GROUP BY s.ResidentID
) c ON p.ResidentID = c.ResidentID
LEFT JOIN sh.Stay st ON st.ResidentID = p.ResidentID
LEFT JOIN sh.StayEmploymentSnapshot es ON es.StayID = st.StayID
GROUP BY p.ResidentID, p.FirstName, p.LastName, c.Cluster
HAVING 
    (c.Cluster = 'Reliable' AND SUM(CASE WHEN es.EmploymentStatus LIKE 'Employed%' THEN 1 END) < 2)
 OR (c.Cluster = 'Chronic' AND SUM(CASE WHEN es.EmploymentStatus = 'Unemployed' THEN 1 END) < 1);


/******************************************************************************************
 5. STAY LENGTH DISTRIBUTION CHECK
    Ensures stay lengths follow expected cluster patterns.
******************************************************************************************/
SELECT 
    p.ResidentID,
    p.FirstName,
    p.LastName,
    c.Cluster,
    AVG(DATEDIFF(day, st.IntakeDate, st.ExitDate)) AS AvgStayLength
FROM sh.Resident p
JOIN (
    SELECT 
        s.ResidentID,
        CASE 
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) > 300 THEN 'Chronic'
            WHEN AVG(DATEDIFF(day, s.IntakeDate, s.ExitDate)) BETWEEN 120 AND 300 THEN 'Struggling'
            ELSE 'Reliable'
        END AS Cluster
    FROM sh.Stay s
    GROUP BY s.ResidentID
) c ON p.ResidentID = c.ResidentID
JOIN sh.Stay st ON st.ResidentID = p.ResidentID
GROUP BY p.ResidentID, p.FirstName, p.LastName, c.Cluster
HAVING 
    (c.Cluster = 'Reliable' AND AVG(DATEDIFF(day, st.IntakeDate, st.ExitDate)) > 200)
 OR (c.Cluster = 'Chronic' AND AVG(DATEDIFF(day, st.IntakeDate, st.ExitDate)) < 120);


/******************************************************************************************
 6. SERVICE ENCOUNTER COMPLETENESS CHECK
    Ensures every stay has at least some service encounters.
******************************************************************************************/
SELECT 
    st.StayID,
    st.ResidentID,
    st.IntakeDate,
    st.ExitDate
FROM sh.Stay st
LEFT JOIN sh.ServiceEncounter se ON se.StayID = st.StayID
GROUP BY st.StayID, st.ResidentID, st.IntakeDate, st.ExitDate
HAVING COUNT(se.ServiceEncounterID) = 0;