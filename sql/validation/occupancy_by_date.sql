-- ============================================================
-- Occupancy Validation — Active Residents by Day
-- Returns one row per calendar day between first intake and last exit.
-- Used to verify the generator produced valid stays across the full
-- date range: no overlapping stays, never exceeding 45 beds.
-- ============================================================

-- Full occupancy by day (all dates)
SELECT
    d.FullDate,
    d.DateKey,
    COUNT(fs.StayKey) AS ActiveResidents
FROM dw.DimDate d
LEFT JOIN dw.FactStay fs
    ON  d.DateKey >= fs.IntakeDateKey
    AND d.DateKey <= fs.ExitDateKey
WHERE d.FullDate BETWEEN (
        SELECT MIN(dd.FullDate) FROM dw.DimDate dd
        JOIN dw.FactStay fs2 ON dd.DateKey = fs2.IntakeDateKey
    )
    AND (
        SELECT MAX(dd.FullDate) FROM dw.DimDate dd
        JOIN dw.FactStay fs2 ON dd.DateKey = fs2.ExitDateKey
    )
GROUP BY d.FullDate, d.DateKey
ORDER BY d.FullDate;

-- ============================================================
-- Problem days only — over capacity (>45) or empty (0)
-- If this returns no rows, occupancy is valid across all dates.
-- ============================================================
SELECT
    d.FullDate,
    d.DateKey,
    COUNT(fs.StayKey)                           AS ActiveResidents,
    CASE
        WHEN COUNT(fs.StayKey) > 45 THEN 'OVER CAPACITY'
        WHEN COUNT(fs.StayKey) = 0  THEN 'EMPTY'
    END                                         AS Flag
FROM dw.DimDate d
LEFT JOIN dw.FactStay fs
    ON  d.DateKey >= fs.IntakeDateKey
    AND d.DateKey <= fs.ExitDateKey
WHERE d.FullDate BETWEEN (
        SELECT MIN(dd.FullDate) FROM dw.DimDate dd
        JOIN dw.FactStay fs2 ON dd.DateKey = fs2.IntakeDateKey
    )
    AND (
        SELECT MAX(dd.FullDate) FROM dw.DimDate dd
        JOIN dw.FactStay fs2 ON dd.DateKey = fs2.ExitDateKey
    )
GROUP BY d.FullDate, d.DateKey
HAVING COUNT(fs.StayKey) > 45 OR COUNT(fs.StayKey) = 0
ORDER BY d.FullDate;
