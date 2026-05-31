# Serenity House PoC — Synthetic Data Design

## Reproducibility

The dataset is fully reproducible. Running `generate_data.py` with the same constants always produces byte-identical output.

| Guarantee | Mechanism |
|---|---|
| Same random draws every run | `random.seed(42)` + `numpy` seed both set at startup |
| Same residents, stays, amounts | All constants in `generate_data.py` (START_DATE, END_DATE, ACTIVE_EXPIRY, WEEKLY_RENT, NUM_RESIDENTS, etc.) |
| Same schema | `sql/oltp/01_schema.sql` and `sql/dw/01_star_schema.sql` are version-controlled |
| Same ETL logic | `sql/dw/02_etl.sql` is version-controlled |

**If you change any constant and regenerate, the output changes.** The Power BI numbers will also change after a semantic model refresh. This is expected — the dataset is still valid, just different. Document any intentional constant changes in git commit messages.

`config.py` (database connection string) is gitignored. All data-shaping constants live in `generate_data.py` and are committed.

---

## Core Design Principle

The dataset is generated once but must work correctly as a proof of concept on **any viewing date** between 2022 and 2029 — including six months or a year after generation. There is no refresh cycle; the same data serves all future demos.

This means:
- "Current resident" is always defined by **today's date at report open time**, not by any status field frozen at generation time
- As time passes, residents naturally age out of "current" as their ExitDate passes TODAY
- The generator ensures realistic bed occupancy (up to 45 beds, no overlapping stays) at any point in the date range

---

## Key Constants (generate_data.py)

| Constant | Value | Meaning |
|---|---|---|
| `START_DATE` | 2022-01-01 | Earliest possible intake date |
| `END_DATE` | 2029-12-31 | Latest possible exit / scheduling boundary |
| `ACTIVE_EXPIRY` | 2029-12-31 | ExitDate assigned to all currently active stays — **must equal END_DATE** |
| `WEEKLY_RENT` | $105.00 | Rent charge per 7-day period |
| `NUM_RESIDENTS` | 500 | Resident pool (seed=42) |

### ACTIVE_EXPIRY must always equal END_DATE

Active stays (residents whose natural exit would be beyond the generation date) are assigned `ExitDate = ACTIVE_EXPIRY`. Setting ACTIVE_EXPIRY < END_DATE would cause some active stays to appear artificially exited before their time, breaking the "current resident" date-range logic.

---

## Defining "Current Resident"

### The rule: date range, not status field

A current resident is one whose stay **brackets today**:

```
IntakeDateKey <= TODAY  AND  ExitDateKey >= TODAY
```

**Do not use `OutcomeCategory = 'Active'`** for this purpose. That field reflects the resident's status at data-generation time. As the current date advances, residents whose ExitDate has now passed will remain `'Active'` in the column even though their stay has ended. The date-range check recalculates correctly on every report open.

### How it works across layers

| Layer | Implementation |
|---|---|
| **Power BI** (calculated column) | `FactStay[IntakeDateKey] <= VALUE(FORMAT(TODAY(), "YYYYMMDD")) && FactStay[ExitDateKey] >= VALUE(FORMAT(TODAY(), "YYYYMMDD"))` → `Is Current Stay` |
| **Power BI** (page filter) | `FactStay[Is Current Stay] = 1` applied at the page level |
| **SQL validation** | `fs.IntakeDateKey <= @TodayKey AND fs.ExitDateKey >= @TodayKey` |

### Why active stays get ExitDate = 2029-12-31

Residents currently in the program need a future ExitDate so that `ExitDateKey >= TODAY` remains true no matter when the report is viewed. ACTIVE_EXPIRY (= END_DATE = 2029-12-31) is that sentinel. The report will work correctly on any date before 2029-12-31.

---

## Future Data Design

The generator creates stays from 2022 through 2029. Stays that haven't started yet (IntakeDateKey > TODAY) and transactions dated in the future (payments, charges, incidents) exist in the database but are invisible in the dashboard.

### Filter patterns by layer

| Layer | Pattern |
|---|---|
| DAX measures (charges, payments, waivers) | `USERELATIONSHIP(...) + DimDate[FullDate] <= TODAY()` |
| Total Assistance (no DimDate relationship) | `FactFinancialAssistance[AssistanceDateKey] <= VALUE(FORMAT(TODAY(), "YYYYMMDD"))` — direct integer key comparison; `USERELATIONSHIP` cannot be used without a model relationship |
| Fact table calculated columns | `FactTable[DateKey] > VALUE(FORMAT(TODAY(), "YYYYMMDD"))` — used as visual-level filters set to `= False` |
| Report-level filter | `FactStay[Is Future Intake] = False` — cascades to all pages |
| SQL validation | `ChargeDateKey <= @TodayKey` where `@TodayKey = CAST(CONVERT(VARCHAR, GETDATE(), 112) AS INT)` |

---

## SQL: Multi-Fact Joins — Always Pre-Aggregate

When joining more than one fact table to FactStay, **pre-aggregate each fact table in a subquery before joining.** Joining multiple fact tables directly multiplies rows (fan-out) and inflates all totals.

```sql
-- WRONG: fan-out inflates totals
SELECT SUM(rc.Amount), SUM(rp.Amount)
FROM dw.FactStay fs
JOIN dw.FactRentCharge  rc ON rc.StayKey = fs.StayKey
JOIN dw.FactRentPayment rp ON rp.StayKey = fs.StayKey
...

-- CORRECT: pre-aggregate each fact table first
LEFT JOIN (
    SELECT StayKey, SUM(Amount) AS TotalCharges
    FROM dw.FactRentCharge WHERE ChargeDateKey <= @TodayKey
    GROUP BY StayKey
) rc ON rc.StayKey = fs.StayKey
LEFT JOIN (
    SELECT StayKey, SUM(Amount) AS TotalPayments
    FROM dw.FactRentPayment WHERE PaymentDateKey <= @TodayKey
    GROUP BY StayKey
) rp ON rp.StayKey = fs.StayKey
```

---

## When to Regenerate

Regenerate the dataset (re-run generate_data.py → ETL → Power BI refresh) when:
- **Approaching END_DATE (2029-12-31)** — active stays will start showing as exited as TODAY passes their ExitDate
- Schema changes require a full rebuild
- Constants (START_DATE, END_DATE, ACTIVE_EXPIRY) are changed

When regenerating, ensure `ACTIVE_EXPIRY = END_DATE` in generate_data.py.

---

## Rebuild Sequence

1. `sql\00_drop_all.sql`
2. `sql\oltp\01_schema.sql`
3. `sql\dw\01_star_schema.sql`
4. `python\generate_data.py`
5. `sql\dw\02_etl.sql`

Then refresh the Power BI semantic model.
