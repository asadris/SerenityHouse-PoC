# DAX Lessons Learned — Serenity House PoC

A running log of DAX patterns used in this project, with explanations for review.

---

## Pattern: Conditional Formatting in Table Visuals

**Used on:** Early Warning page flag columns

Two approaches depending on column type:

**Numeric columns (Incidents, Positive Tests, Missed Meetings):** Use Rules-based background color.
- Format pane → Cell elements → select column → Background color → fx → Rules
- Rule: value > 0 → `#FFB3B3` (light red). Value = 0 → no fill or `#B3FFB3` (light green).
- Avoid pure red — `#FFB3B3` is easier to read and less alarming.

**Text columns (Arrears Trend):** Rules don't work on text. Use a companion color measure instead:
```dax
Arrears Trend Color =
    IF([Arrears] > [Arrears 30 Days Ago], "#FFB3B3", "#B3FFB3")
```
Then in the fx dialog, set format style to **Field value** and point at this measure.

**Risk Score heat map:** Use Rules with multiple bands:
- 0 → no fill
- 1 → light yellow (`#FFF3B3`)
- 2 → orange (`#FFD9B3`)
- 3 or more → red (`#FFB3B3`)

This gives a heat-map effect — worst cases are visually obvious without reading every number.

---

## Pattern: USERELATIONSHIP (inactive relationships)

**When you need it:** All date relationships from fact tables to DimDate are INACTIVE in this model. Any measure that needs to filter or group by date must activate the relationship explicitly.

**Why inactive?** A table can only have one active relationship to DimDate. Since FactIncident has only one date key (IncidentDateKey), the relationship could technically be active — but the pattern was set up this way intentionally so all fact tables are consistent.

**Template:**
```dax
CALCULATE(
    COUNTROWS(FactIncident),
    USERELATIONSHIP(FactIncident[IncidentDateKey], DimDate[DateKey]),
    DimDate[FullDate] >= TODAY() - 30,
    DimDate[FullDate] <= TODAY()
)
```

**Key rule:** USERELATIONSHIP goes inside CALCULATE as a filter argument. It temporarily activates the relationship for that calculation only.

**Fact tables requiring USERELATIONSHIP:** FactRentCharge, FactRentPayment, FactRentWaiver, FactIncident, FactDrugTest.

---

## Pattern: 30-Day Rolling Window

**Used in:** `Incidents Last 30 Days`, `Positive Tests Last 30 Days`, `Missed Meetings Last 30 Days`

```dax
DimDate[FullDate] >= TODAY() - 30,
DimDate[FullDate] <= TODAY()
```

Simple and readable. TODAY() - 30 gives a dynamic rolling window — no hardcoded dates, updates automatically every day.

**Why not DATESINPERIOD or DATEADD?** Those work cleanly when the DimDate relationship is active. With inactive relationships, the explicit >= / <= filter on DimDate[FullDate] after USERELATIONSHIP is simpler and less error-prone.

---

## Pattern: Filtering Through a Dimension (vs. filtering the fact)

**Used in:** `Missed Meetings Last 30 Days`

```dax
DimIncidentType[IncidentName] = "Incomplete Weekly Meeting"
```

This filters FactIncident rows **through** DimIncidentType using the existing relationship. The alternative would be to store the incident type name directly on the fact table and filter `FactIncident[IncidentName]` — but that denormalizes the star schema.

**Why this matters:** If the incident type name ever changes in DimIncidentType, it only needs updating in one place (the dimension), and the measure picks it up automatically. Filtering by key (e.g., `FactIncident[IncidentTypeKey] = 7`) would be faster but fragile — the key could change if data is rebuilt.

---

## Pattern: Arrears at a Point in Time (Snapshot Arrears)

**Used in:** `Arrears 30 Days Ago`

The standard `[Arrears]` measure computes: Total Charges − Total Payments − Total Waivers − Total Assistance, all up to today.

To get arrears *as of 30 days ago*, we can't use DATEADD easily because:
1. The date relationships are inactive (DATEADD requires an active date table relationship)
2. The date keys are integers (YYYYMMDD), not native date columns

**Solution:** Convert 30-days-ago to an integer key and filter each fact table directly:

```dax
VAR DateKey30 = VALUE(FORMAT(TODAY() - 30, "YYYYMMDD"))
RETURN
CALCULATE(SUM(FactRentCharge[Amount]), ..., FactRentCharge[ChargeDateKey] <= DateKey30)
- CALCULATE(SUM(FactRentPayment[Amount]), ..., FactRentPayment[PaymentDateKey] <= DateKey30)
- CALCULATE(SUM(FactRentWaiver[Amount]), ..., FactRentWaiver[WaiverDateKey] <= DateKey30)
- CALCULATE(SUM(FactFinancialAssistance[Amount]), ..., FactFinancialAssistance[AssistanceDateKey] <= DateKey30)
```

**How to use it on the Early Warning page:** Put `[Arrears]` and `[Arrears 30 Days Ago]` side by side in the table. If `[Arrears]` > `[Arrears 30 Days Ago]`, the resident's balance is climbing — that's the flag. You can also create a simple derived measure:

```dax
Arrears Climbing =
    IF([Arrears] > [Arrears 30 Days Ago], "↑ Climbing", "Stable")
```

---

## Pattern: Calculated Column for "Is Future X"

**Used on:** FactStay, FactIncident, FactRentPayment, FactDrugTest

```dax
column 'Is Future Incident' = FactIncident[IncidentDateKey] > VALUE(FORMAT(TODAY(), "YYYYMMDD"))
    dataType: boolean
```

**Why not a measure?** Table visuals in Power BI can't use relative date filters when the date field is an integer key — only proper date columns get the native "is in the last N days" filter option. A calculated boolean column lets us use it as a visual-level or report-level filter with a simple True/False slicer.

**Why convert TODAY() to an integer?** The date key is stored as YYYYMMDD (e.g., 20260528). Comparing it directly to TODAY() would compare an integer to a date — type mismatch. `VALUE(FORMAT(TODAY(), "YYYYMMDD"))` converts today to the same integer format for a valid comparison.

**TMDL syntax note:** The expression goes inline after `= `, NOT as a separate `expression:` property. Using `expression:` causes "Property 'expression' is unknown" error in Power BI's TMDL parser.

---

## Pattern: ALLEXCEPT vs. plain CALCULATE in Drillthrough Context

**Lesson learned from Resident Profile page:**

`[Resident Arrears]` uses `ALLEXCEPT(DimResident, DimResident[ResidentKey])` — this was designed for a table visual showing all residents at once. On a drillthrough page, the filter context already has one resident selected, so ALLEXCEPT **clears** that context and returns the sum for all residents.

**Fix:** Use `[Arrears]` directly on the drillthrough page. It respects the existing filter context without needing ALLEXCEPT.

**Rule of thumb:** ALLEXCEPT is for "ignore all filters except this one column." In a drillthrough scenario, the filter IS on that column — so ALLEXCEPT fights the context instead of helping it.
