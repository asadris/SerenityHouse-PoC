# Serenity House Analytics PoC — Technical Architecture

*Last updated: 2026-06-01*

---

## Overview

The Serenity House PoC is a full-stack analytics system demonstrating how a 45-bed nonprofit recovery residence could move from manual Excel reporting to a modern data pipeline. The system is built entirely on Microsoft tools (SQL Server, Python, Power BI) and is designed to be explainable to non-technical stakeholders.

All data is synthetic. The Python generator produces realistic but entirely fictional residents, stays, and transactions. The report is designed to work correctly on any viewing date between 2022 and 2029 without modification or data refresh.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│               Python Data Generator (v7)                 │
│  generate_data.py — seed=42, 500 residents, 700 stays   │
│  Behavioral clusters → drug tests, incidents, rent,     │
│  employment, outcomes, donations, financial assistance  │
└────────────────────────┬────────────────────────────────┘
                         │  pyodbc (Windows Auth)
                         ▼
┌─────────────────────────────────────────────────────────┐
│         SQL Server OLTP  (schema: sh)                   │
│         Database: Serenity1                             │
│         Server: PETRISLAP2025\PETRIS2022               │
│                                                         │
│  Core: Resident, Stay, Bed, Room, House, CaseManager   │
│  Financial: RentCharge, RentPayment, RentWaiver        │
│  Clinical: DrugTest, Incident, IncidentType            │
│  Services: ServiceType, ServiceEncounter               │
│  Employment: StayEmploymentSnapshot                    │
│  Outcomes: Outcome                                     │
│  Fundraising: Donor, FundraisingEvent,                 │
│               FundraisingDonation                      │
│  Financial Assist: FinancialAssistanceProgram,         │
│                    ProgramPayment                      │
│  Identity: SecurityIdentityMap                         │
│  Lookups: ReferralSource                               │
└────────────────────────┬────────────────────────────────┘
                         │  T-SQL ETL (02_etl.sql)
                         ▼
┌─────────────────────────────────────────────────────────┐
│       SQL Server Data Warehouse  (schema: dw)           │
│                                                         │
│  Dimensions (9):                                        │
│    DimDate, DimResident, DimBed, DimRoom, DimHouse,    │
│    DimCaseManager, DimIncidentType,                     │
│    DimReferralSource, DimDonor,                         │
│    DimFundraisingEvent                                  │
│                                                         │
│  Facts (8):                                             │
│    FactStay, FactRentCharge, FactRentPayment,          │
│    FactRentWaiver, FactIncident, FactDrugTest,         │
│    FactDonation, FactFinancialAssistance               │
└────────────────────────┬────────────────────────────────┘
                         │  DirectQuery / Import
                         ▼
┌─────────────────────────────────────────────────────────┐
│     Power BI Semantic Model  (PBIP/TMDL format)         │
│     powerbi/SerenityPOC2.SemanticModel/                 │
│                                                         │
│  50+ DAX measures, calculated columns,                 │
│  inactive date relationships + USERELATIONSHIP         │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│        Power BI Report  (14 pages)                      │
│        powerbi/SerenityPOC2.Report/                     │
│                                                         │
│  Synthetic Data Notice, Early Warning, Master Roster,  │
│  Arrears, Rent, Behaviors, Bed/Stay, Demographics,     │
│  Referrals, Areas Served, Donations, Funding,          │
│  Resident Profile (drillthrough), Program Outcomes     │
└─────────────────────────────────────────────────────────┘
```

---

## Layer 1: Python Data Generator (v7)

**File:** `python/generate_data.py`

### Design philosophy

The generator runs once and produces a dataset that works correctly on any viewing date from 2022 through 2029. There is no scheduled refresh cycle. The report uses `<= TODAY()` throughout to self-filter as time passes.

### Behavioral clustering

Three in-memory clusters drive all behavioral data. Clusters are **never stored** in the database — they exist only during generation.

| Cluster | Weight | Rent Payment | Drug Positive | Incidents | Employment |
|---|---|---|---|---|---|
| Reliable | 60% | 95% | 5% | 0–1/stay | Mostly full-time |
| Struggling | 30% | 60% | 20% | 0–3/stay | Mixed |
| Chronic | 10% | 10% | 40% | 1–6/stay | Mostly unemployed |

### Generation sequence

The order matters — later steps depend on data from earlier steps:

```
[1/9]  Housing setup         — 1 house, 15 rooms, 45 beds
[2/9]  Case managers         — 6 case managers
[3/9]  Residents             — 500 residents + SecurityIdentityMap records
[4/9]  Stays                 — 700 stays (seasonal occupancy model)
[5/9]  Drug tests            — cluster-driven frequency and positive rate
[6/9]  Incidents             — cluster-driven count and type
[7/9]  Service encounters    — daily AA/NA, house meetings, curfew check-ins
[8/9]  Employment, rent,     — employment snapshots, weekly rent charges/payments/waivers
        exit outcomes         — finalize_exit_outcomes() runs LAST (needs all behavior data)
[9/10] Financial assistance  — ~25% of stays receive 1–3 program payments
[10/10] Fundraising          — 300 donors, 20 events, 2,500 donations
```

### Behavior-driven exit modeling (v7 key feature)

`finalize_exit_outcomes()` is the most important design decision in the generator. It replaces the earlier approach of assigning exit types upfront (which could produce illogical combinations like "Completed program + No program completion").

**How it works:**
1. After all behavior data is generated, query the actual incident count, rent payment rate, and drug test positive rate per stay from the database
2. Compute a behavior score (base probability from cluster ± modifiers from actual behavior)
3. Draw from that probability to determine Completed / Terminated / Transferred
4. Write final StayStatus and ExitReason back to sh.Stay
5. Insert sh.Outcome records (Exit Destination, Employment at Exit, Sobriety Length, Program Completion)

**Behavior score modifiers:**
```
Base:  Reliable=0.75, Struggling=0.40, Chronic=0.15

Payment rate modifier:
  ≥90% → +0.12 | 60–89% → +0.05 | 30–59% → -0.10 | <30% → -0.20

Incident count modifier:
  0 incidents → +0.10 | 1–2 → no change | each above 2 → -0.10

Drug test positive rate modifier:
  <5% → +0.08 | 30–50% → -0.12 | >50% → -0.20

Final probability clamped to [0.05, 0.95]
```

### Occupancy model

Stays are scheduled week-by-week from START_DATE to END_DATE. Each week, a target occupancy fraction is computed based on season:

| Season | Occupancy Target |
|---|---|
| Winter (Nov–Feb) | 90–100% — occasionally 100% for multi-week stretches |
| Fall (Sep–Oct) | 78–87% |
| Summer (Jun–Aug) | 68–80% |
| Spring (Mar–May) | 55–70% — peak departure season |

The scheduler maintains a bed calendar (next-free date per bed) and a resident pool. New residents are preferred over returnees to keep repeat-stay rate around 25%. Maximum 4 stays per resident.

---

## Layer 2: SQL Server OLTP (sh schema)

**File:** `sql/oltp/01_schema.sql`

The OLTP schema is a normalized operational model capturing the full resident lifecycle. In production, this would be the transactional database that staff write to. In the PoC, the Python generator writes to it directly.

### Key design decisions

**All stays have a real exit date.** There is no `ExitDate = NULL` sentinel for active stays. Active stays get a computed future exit date (intake + projected length of stay), capped at ACTIVE_EXPIRY (2029-12-31). This keeps the date arithmetic clean throughout the system.

**StayStatus is a generation-time snapshot.** The `StayStatus` column on `sh.Stay` reflects the status at the moment `finalize_exit_outcomes()` ran. Do not use it for "is this resident currently active?" — use the date-range check instead (IntakeDateKey <= TODAY AND ExitDateKey >= TODAY).

**Identity masking.** `sh.SecurityIdentityMap` stores a UUID (`PublicResidentID`) for each resident. In a production deployment, external-facing reports would use the UUID, never the internal integer `ResidentID`. This is implemented but not activated in the PoC (synthetic data has no real PII to protect).

**Referral sources seeded.** 15 referral sources are seeded as part of the schema (Jail, Prison, Drug Court, Probation/Parole, treatment providers, Hospital, Street, Self-Referral, Family/Friend, Other). The generator uses weighted sampling against these IDs.

### Table groups

| Group | Tables |
|---|---|
| Housing | House, Room, Bed |
| People | Resident, CaseManager |
| Program | Stay, Outcome, ReferralSource |
| Clinical | DrugTest, Incident, IncidentType |
| Services | ServiceType, ServiceEncounter |
| Employment | StayEmploymentSnapshot |
| Rent | RentCharge, RentPayment, RentWaiver |
| Fundraising | Donor, FundraisingEvent, FundraisingDonation |
| Financial Assist | FinancialAssistanceProgram, ProgramPayment |
| Security | SecurityIdentityMap |

---

## Layer 3: SQL Server Data Warehouse (dw schema)

**Files:** `sql/dw/01_star_schema.sql`, `sql/dw/02_etl.sql`

The DW uses a classic star schema. All analytical queries run against this layer — the Power BI semantic model connects here, not to the OLTP schema.

### Star schema diagram

```
                    DimDate
                      │
          ┌───────────┼──────────────┐
          │           │              │
    FactRentCharge  FactStay    FactIncident
    FactRentPayment   │         FactDrugTest
    FactRentWaiver    │         FactDonation
                      │         FactFinancialAssistance
                    DimResident
                    DimBed ─── DimRoom ─── DimHouse
                    DimCaseManager
                    DimReferralSource
                    DimIncidentType
                    DimDonor
                    DimFundraisingEvent
```

### Key design decisions

**All date relationships are inactive (except FactDonation).** A fact table can only have one active relationship to DimDate. Rather than making arbitrary choices about which date role is "primary" for each fact table, all date relationships are set to inactive. Every DAX measure that needs date filtering uses `USERELATIONSHIP()` explicitly. This is more verbose but eliminates ambiguity.

**Integer date keys (YYYYMMDD format).** Date keys are stored as integers (e.g., 20260601 for June 1, 2026). This is a common DW pattern that makes date comparisons fast and prevents NULL date issues. The tradeoff: native Power BI relative date filters don't work on integer keys — mitigated with calculated boolean columns (Is Future Intake, Is Future Incident, etc.).

**FactStay is the hub.** All behavioral and financial fact tables link through `StayKey` on `FactStay`. There is no direct path from e.g. `FactIncident` to `DimResident` — you must traverse through `FactStay`. This is intentional: an incident belongs to a stay, not directly to a resident, and a resident can have multiple stays.

**ETL is additive-replace, not incremental.** The ETL truncates and reloads the DW from the OLTP schema on each run. This is appropriate for a PoC; a production system would use incremental loading for large fact tables.

---

## Layer 4: Power BI Semantic Model (PBIP/TMDL)

**Files:** `powerbi/SerenityPOC2.SemanticModel/definition/`

### PBIP format

The report is saved in Power BI Project (PBIP) format, which decomposes the semantic model into human-readable TMDL (Tabular Model Definition Language) files. This means:

- Every table, column, measure, and relationship is a text file tracked in git
- Changes to DAX measures appear as meaningful diffs in version history
- The semantic model can be inspected without opening Power BI Desktop

### Calculated columns (on fact tables)

These columns are computed once on load and stored in the model. They enable filtering patterns that don't work with measures:

| Column | Table | Expression | Purpose |
|---|---|---|---|
| Is Current Stay | FactStay | IntakeDateKey <= TODAY_key AND ExitDateKey >= TODAY_key | Powers all active resident logic |
| Roster Status | FactStay | IF(Is Current Stay = 1, "Active", "Exited") | Slicer on Master Roster page |
| Resident Full Name | FactStay | RELATED(DimResident[Full Name]) | Table visuals — avoids cross-table fan-out |
| Is Future Intake | FactStay | IntakeDateKey > TODAY_key | Report-level filter = False |
| Is Future Incident | FactIncident | IncidentDateKey > TODAY_key | Visual-level filter = False |
| Is Future Payment | FactRentPayment | PaymentDateKey > TODAY_key | Visual-level filter = False |
| Is Future Test | FactDrugTest | TestDateKey > TODAY_key | Visual-level filter = False |
| Incident Date | FactIncident | DATE from IncidentDateKey | Proper date type for table display |
| Payment Date | FactRentPayment | DATE from PaymentDateKey | Proper date type for table display |

### Key DAX patterns

**USERELATIONSHIP for all date filtering:**
```dax
CALCULATE(
    COUNTROWS(FactIncident),
    USERELATIONSHIP(FactIncident[IncidentDateKey], DimDate[DateKey]),
    DimDate[FullDate] <= TODAY()
)
```

**Is Current Stay (integer date key comparison):**
```dax
FactStay[IntakeDateKey] <= VALUE(FORMAT(TODAY(), "YYYYMMDD"))
    && FactStay[ExitDateKey] >= VALUE(FORMAT(TODAY(), "YYYYMMDD"))
```

**Arrears (multi-fact aggregation):**
```dax
[Arrears] =
    [Total Charges]
    - [Total Payments]
    - [Total Waivers]
    - [Total Assistance]
```
Each component uses USERELATIONSHIP with its respective date key. Fact tables are never joined directly in DAX — each component measure is independent, avoiding fan-out.

**Risk Score (Early Warning):**
```dax
[Risk Score] =
    IF([Arrears] > 0, 1, 0)
    + IF([Arrears] > [Arrears 30 Days Ago], 1, 0)   -- climbing
    + IF([Incidents Last 30 Days] > 0, 1, 0)
    + IF([Positive Tests Last 30 Days] > 0, 1, 0)
    + IF([Missed Meetings Last 30 Days] > 0, 1, 0)
    + IF([Days in Program] < 30, 1, 0)               -- new arrival
```
Score range 0–6, sorted descending so highest-risk residents float to top.

**TOPN with tie handling:**
```dax
Top Referral Source =
    MAXX(
        TOPN(1, ALL(DimReferralSource), CALCULATE(COUNTROWS(FactStay))),
        DimReferralSource[SourceName]
    )
```
`MAXX` instead of `SELECTEDVALUE` ensures a single value is returned even when there's a tie at position 1.

**Drillthrough-safe arrears:**
On the Resident Profile drillthrough page, `[Arrears]` is used instead of `[Resident Arrears]`. The latter uses `ALLEXCEPT(DimResident, DimResident[ResidentKey])` which clears the drillthrough filter context. `[Arrears]` respects whatever filter context is active.

### Measure organization

All measures live in the `My Measures` table (a disconnected table used as a measure container). Measures are organized into display folders:

- `Arrears` — charges, payments, waivers, assistance, net arrears, trends
- `Behaviors` — incidents, drug tests, service encounters
- `Donations` — donation totals, donor counts, event breakdowns
- `Early Warning` — risk score, rolling 30-day flags
- `Funding` — financial assistance measures
- `Occupancy` — active beds, bed status, occupancy %
- `Rent` — rent collection, payment rate
- `Resident` — individual resident measures for Resident Profile page

---

## Layer 5: Power BI Report (14 pages)

**Files:** `powerbi/SerenityPOC2.Report/definition/pages/`

### Page filtering architecture

Report-level filter (applies to all 14 pages):
- `FactStay[Is Future Intake] = False` — excludes residents whose intake date hasn't happened yet

Visual-level filters (Resident Profile drillthrough page only):
- `FactIncident[Is Future Incident] = False` — excludes future-dated incidents from the incident table
- `FactRentPayment[Is Future Payment] = False` — excludes future payments from the payment table

No other pages need visual-level future filters because their measures already apply `<= TODAY()` date constraints.

### Drillthrough pattern

The Resident Profile page uses Power BI's drillthrough feature. Users right-click any resident name anywhere in the report and select "Drill through → Resident Profile" to navigate to that resident's individual summary page.

The drillthrough field is `DimResident[Full Name]`. Power BI automatically passes the selected resident as a filter to the destination page. No custom navigation or bookmarks are required.

### Page navigation

Pages are navigated in Power BI Desktop via `Ctrl+Tab` (highlights next tab) then `Enter` (navigates to it). `Ctrl+PageDown` does not work in Power BI Desktop for page navigation.

---

## Automation Scripts

### rebuild.py

**File:** `python/rebuild.py`

Interactive Python script that runs the full 5-step rebuild sequence. Prompts for confirmation before dropping the database. Streams generator output live so progress is visible.

```
Confirm → Drop all (00_drop_all.sql) → OLTP schema → DW schema
       → generate_data.py (live output) → ETL (02_etl.sql)
```

Uses `sqlcmd` (must be on PATH) for SQL steps and `subprocess.Popen` with line-buffered streaming for the generator.

### Take-Screenshots.ps1

**File:** `scripts/Take-Screenshots.ps1`

PowerShell script that automates portfolio screenshot capture from Power BI Desktop. Maximizes the PBI window, takes a full-screen PNG, then advances to the next page via `Ctrl+Tab` + `Enter`.

Usage: navigate to page 1 (Synthetic Data Notice) in PBI Desktop, then run:
```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\Take-Screenshots.ps1"
```

Produces 14 numbered PNGs in the `screenshots/` folder.

---

## Future-Data Design

This is the most architecturally unusual aspect of the system. It's documented thoroughly in `docs/synthetic-data-design.md`, but summarized here:

The generator creates data spanning 2022–2029. This means the database always contains:
- Historical stays (intake and exit both in the past)
- Current stays (intake in past, exit in future — these are "active residents")
- Future stays (intake in future — residents not yet admitted)
- Future transactions (charges, payments, tests dated ahead of today)

The report hides all future data using a layered filter strategy:

| Layer | Filter | Scope |
|---|---|---|
| Report-level | `Is Future Intake = False` | All 14 pages |
| DAX measures | `DimDate[FullDate] <= TODAY()` via USERELATIONSHIP | All financial/behavioral aggregations |
| Visual-level | `Is Future Incident = False`, `Is Future Payment = False` | Resident Profile tables only |

This means the report shows exactly what it would show if it connected to a live operational database — without needing to maintain or refresh a real live database.

---

## Production Path

The PoC is intentionally scoped to demonstrate the architecture, not to be a production deployment. The intended production evolution:

```
Phase 1 (PoC — current):
  Python generator → SQL Server → Power BI Desktop

Phase 2 (Production MVP):
  Excel / intake forms → SQL Server → Power BI Service (scheduled refresh)
  + Row-level security for case manager access scoping
  + Power BI Pro licenses (discounted via Microsoft for Nonprofits)

Phase 3 (Full build):
  Web/Access intake forms → SQL Server → Power BI Service
  + Toast POS integration for The Recovery Cafe
  + HMIS data standard compliance
  + Automated nightly ETL
```

The OLTP schema is designed to be compatible with HMIS (Homeless Management Information System) data standards, which many recovery residences are required to report against. A production deployment would validate field definitions against the current HMIS Data Standards Manual.

---

## Key Decisions Log

| Decision | Choice | Rationale |
|---|---|---|
| All date relationships inactive | Yes | Eliminates ambiguity; all measures explicitly activate what they need |
| Integer date keys (YYYYMMDD) | Yes | Fast comparisons, no NULL issues; tradeoff: no native PBI relative date filter |
| Future data in dataset | Yes | Simulates a live system without needing live data or periodic refresh |
| StayStatus vs. Is Current Stay | Use Is Current Stay | StayStatus is a generation-time snapshot; date math is always correct |
| Fact tables through FactStay | Yes | Incidents and payments belong to stays, not directly to residents |
| PBIP format | Yes | Human-readable TMDL files; all DAX tracked in git |
| Behavior-driven exits (v7) | Yes | Eliminates logical inconsistencies (e.g., Completed + No program completion) |
| No real PII | Yes | All data synthetic; identity masking implemented but not activated in PoC |

---

*See also: `docs/dax-lessons-learned.md`, `docs/synthetic-data-design.md`, `docs/requirements-summary.md`*
