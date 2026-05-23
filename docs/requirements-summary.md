# Serenity House PoC — Requirements Summary
*Synthesized from all project documents, Copilot conversation history, SQL schemas, Python generators, and Power BI semantic model. Prepared: 2026-05-20*

---

## 1. What This Project Is

A proof-of-concept analytics system for **Serenity House**, a transitional recovery residence (currently ~45 beds). The longer-term vision is a combined system covering:

- **Transitional/Halfway House** — resident management, services, compliance, outcomes
- **Fundraising** — donors, events, donations, community engagement
- **Restaurant** *(to be scoped — see Open Questions)*

The PoC uses **100% synthetic data** — no real resident information. The purpose is to show Serenity House leadership (April) what a modern data and analytics system would look like before committing to a full build.

---

## 2. Current Architecture (What Copilot Built)

```
Python Generator → SQL Server OLTP (sh schema) → ETL → DW Star Schema (dw schema) → Power BI Dashboards
```

- **Server:** `PETRISLAP2025\PETRIS2022`
- **Database:** `Serenity1`
- **OLTP schema:** `sh`  
- **DW schema:** `dw`
- **Power BI file:** `SerenityPOC2.pbix` / `SerenityPOC2.pbip` (PBIP format in DevopsTestSerenity/)

---

## 3. OLTP Schema Requirements (sh)

### What the documents specify (authoritative)

| Domain | Tables | Notes |
|---|---|---|
| Housing | House, Room, Bed, **StayRoomAssignments** | Assignments track room/bed moves during a stay (MoveInDate, MoveOutDate, ReasonForMove) |
| Residents | Resident | Demographics, contact, emergency contact, origin info, national ID, alternate ID |
| Stays | Stay | StayStartDate, StayEndDate (NULL if active), StayStatus, ExitReason |
| Case Management | CaseManager, **CaseAssignments**, **CaseNotes**, Incident, IncidentType | CaseNotes has ConfidentialFlag; Incidents have ActionTaken, FollowUpRequired |
| Services | ServiceType, **ServiceAttendance** | Tracks compliance with mandatory vs optional programming |
| Employment | **EmploymentRecord** | Actual wage (decimal), hours/week (int), employer, job title, dates — not just snapshot bands |
| Drug Testing | DrugTest | TestType, Result, SubstancesDetected |
| Outcomes | Outcome | OutcomeType, OutcomeValue — can be multiple outcomes per stay |
| Financial | RentCharge, RentPayment, RentWaiver, **FinancialAssistanceProgram**, **ProgramPayment** | Waivers linked to specific charges; third-party payers tracked separately |
| Fundraising | Donor, FundraisingEvent, Donation | Donor types: Individual, Business, Church, Foundation, Anonymous |
| Security | SecurityIdentityMap | PublicResidentID (UUID masking) |

### What the current schema has vs. what's specified

| Requirement | Current Schema | Gap |
|---|---|---|
| Room moves during stay | ❌ Single BedID on Stay | Need StayRoomAssignments table |
| Case notes | ❌ Missing | Need CaseNotes table |
| Case assignments over time | ❌ Single CaseManagerID on Stay | Need CaseAssignments table |
| Third-party payer programs | ⚠️ FinancialAssistance only (combined) | Should split into FinancialAssistanceProgram + ProgramPayment |
| Employment actual wages | ❌ Only WageBand/HoursPerWeekBand | Need real decimal wage, int hours |
| Emergency contacts | ❌ Missing | Should be on Resident |
| Alternate ID | ❌ Missing | Should be on Resident |
| StayStatus field | ❌ Missing (inferred from ExitDate NULL) | Explicit Active/Completed/Terminated status is cleaner |

### Decision: Keep or rebuild?
The 5th gen schema is ~80% correct. **Recommended:** Keep the core structure, add the missing tables, fix StayStatus, and make ExitDate nullable properly. Do **not** start schema from zero — the generator and Power BI are already aligned to it.

---

## 4. Behavioral Clustering Model (Generator Requirements)

The generator uses **in-memory only** clusters — not stored in the database:

| Cluster | Weight | Rent Pay Rate | Drug Positive | Incidents | Employment |
|---|---|---|---|---|---|
| Reliable | 60% | 95% | 5% | 0–1 | Mostly FT/PT employed |
| Struggling | 30% | 60% | 20% | 0–3 | Mixed |
| Chronic | 10% | 10% | 40% | 1–6 | Mostly unemployed |

### Computed (not stored) metrics per stay:
- Total rent charges, payments, waivers, assistance, arrears
- Payment ratio, waiver ratio, assistance ratio
- Risk score (0–100 composite)

### Inferred cluster (DAX / SQL views):
- Reliable: PaymentRatio ≥ 0.85
- Struggling: PaymentRatio 0.40–0.84
- Chronic: PaymentRatio < 0.40

### Known generator bugs to fix:
1. **All stays get an ExitDate** — active residents should have `ExitDate = NULL`
2. **Cluster weights** in the final script are 60/30/10, but some docs say 50/25/25 — need to decide canonical weights
3. **Two separate fundraising generators** (main script has 20 donors/4 events/100 donations; fundraising.py has 2000 donors/50 events/25000 donations) — need to merge or choose one

---

## 5. Power BI Requirements

### Semantic model tables (current)
DimBed, DimDate, DimDonor, DimFundraisingEvent, DimHouse, DimResident, DimRoom, FactDonation, FactFinancialAssistance, FactRentCharge, FactRentPayment, FactRentWaiver, FactStay, My Measures

### Dashboard pages required (from POC Description doc)

| Page | Key Visuals |
|---|---|
| 1. Engagement Overview | Attendance rates, required vs optional, by house and case manager |
| 2. Behavior & Stability | Incident trends, drug test positivity, combined risk indicators |
| 3. Financial Responsibility | Rent charges vs payments, waivers, assistance, compliance patterns, arrears |
| 4. Employment Progress | Employment snapshots, wage/hours bands, employment at exit |
| 5. Program Outcomes | Successful exits, destination types, length of stay, referral source performance |
| 6. Fundraising | Total donations, donor segmentation, event ROI, YoY growth *(exists in model, needs page)* |

### DAX Measures (current — keep these)
- Active Beds Today, Total Beds, Occupancy %, Bed Status
- Daily Occupancy *(has known bug — see below)*
- Total Charges, Total Payments, Total Waivers, Arrears
- Resident-level financial measures
- Donation measures (Total Donations, Total Donors, YoY Growth, etc.)

### Known DAX bugs to fix:
1. **Daily Occupancy** — broken because generator always sets ExitDate. The measure itself (`DISTINCTCOUNT(FactStay[StayID])` filtered by IntakeDateKey ≤ DateKey ≤ ExitDateKey) is logically correct — the bug is upstream in the data. Fix the generator first, then the measure works.
2. **Active Beds Today** uses `ExitDateKey` — same root cause. Once ExitDate is NULL for active stays, need a NULL-safe version.

### Relationships (current — mostly correct)
- FactStay → DimDate (IntakeDateKey active, ExitDateKey inactive) — this is correct pattern
- FactStay → DimBed, DimResident, DimRoom, DimHouse (chain)
- Fact tables → FactStay (StayKey)
- FactDonation → DimDonor, DimFundraisingEvent, DimDate

---

## 6. Reporting Tools

### Power BI Dashboards *(in progress)*
Interactive executive and management dashboards. Best for "how are we doing?" questions, trend analysis, and stakeholder presentations. See Section 5 for current pages and DAX measures.

### Power BI Report Builder / Paginated Reports *(planned)*
For operational and financial reports that need precise formatting, pagination, and clean PDF export. Power BI dashboards can't replace these. Planned use cases:
- Individual resident rent ledger (printable, handed to resident)
- Monthly financial statement for the board
- Case manager caseload report
- Any formal document requiring exact layout, headers, footers, page breaks

### MS Access *(under consideration)*
See Section 6a below.

---

## 6a. MS Access *(To Be Scoped)*

MS Access is being considered as both a front-end and reporting tool. Key advantages for a small nonprofit: non-technical staff can maintain and modify forms and reports without calling a developer, no web development required, built-in reporting for operational/financial documents, and it's already part of the Microsoft ecosystem most organizations have.

### Possible roles
- **Data entry front-end** — forms-based UI for resident, stay, rent, and case management data entry
- **Operational reporting** — rent ledgers, caseload reports, financial summaries — printable and exportable to PDF without Power BI licensing
- **Fallback reporting layer** — if Power BI licensing costs are prohibitive, Access reports can cover most operational reporting needs

### Backend options for Access
| Backend | Cost | Notes |
|---|---|---|
| SQLite (via ODBC) | Free | Single file, zero administration, no server needed. Perfectly adequate for Serenity House data volumes. Access links via ODBC driver. |
| SQL Server Express | Free | More robust for concurrent users, proper server engine. More infrastructure to manage. |
| Access native (.accdb) | Free (included) | Simplest setup, but 2GB limit and fragile with multiple concurrent users. |

**Recommended for production simplicity: Access + SQLite.** Zero ongoing cost, no server to maintain, non-technical staff can manage it, and data volumes at 45 beds will never stress SQLite.

### Relationship to Power BI
Access and Power BI are complementary, not competing. Power BI handles interactive dashboards and executive reporting; Access handles day-to-day operational forms and printed reports. Both can sit on top of the same underlying data.

---

## 6b. Licensing & Cost Considerations *(document to be written)*

A standalone document is planned that covers the full tool/cost landscape for Serenity House's decision-making. Topics to cover:

### Power BI
- **Power BI Desktop** — free, single-user authoring only
- **Power BI Pro** — ~$10/user/month retail; significantly discounted for nonprofits via Microsoft for Nonprofits program
- **Publish to Web** — free public sharing with no row-level security; suitable for donor-facing or public dashboards
- **Power BI Report Server** — on-premises option, requires Premium licensing

### Microsoft for Nonprofits
- Discounted/free Microsoft 365 plans for 501(c)(3) organizations
- Power BI Pro often included or heavily discounted
- **Azure for Nonprofits**: $3,500/year in Azure credits for qualifying organizations
- Apply via Microsoft for Nonprofits program (nonprofits.microsoft.com)

### Access
- Included with Microsoft 365 Business Standard and above — likely already licensed
- No per-user reporting costs
- Non-technical staff can modify forms and reports independently
- Lower long-term maintenance cost than Power BI for operational reports

### SQLite
- Completely free, no licensing, no server costs
- Single file database — easy to back up, move, archive

---

## 7. Excel as Data Source *(Production Reality)*

In production, source data will most likely come from Excel spreadsheets rather than a transactional OLTP database. The OLTP schema in the PoC serves as a **reference model** — it defines what data needs to be captured, not necessarily how it will be entered in production.

The simplest viable production architecture is:
```
Excel (OneDrive) → Power BI Dataset → Power BI Reports
```
Power BI connects natively to OneDrive-hosted Excel files with automatic refresh. No SQL Server required for an organization of this size if data volume and complexity don't demand it. The DW star schema is the enterprise path — available if needed, but not mandatory.

Likely candidates for Excel-based data entry:
- Resident rent ledger — weekly charges/payments/waivers/arrears
- Occupancy tracker — room/bed status
- Donation log — donor entry
- Case manager caseload summary

---

## 8. The Recovery Cafe *(To Be Scoped)*

The user mentioned this is a "combination halfway or transitional house/restaurant/fundraising." This is **not documented** in any existing files. Open questions:

- Is the restaurant operated by residents as a training/employment program?
- Is it a separate business entity or part of Serenity House?
- Does it generate revenue tracked in this system?
- What data does it need: POS sales? Employee shifts? Inventory?
- Does it use Toast (Eric from Toast was contacted Feb 4, 2026)?

**This needs a conversation before any schema work begins on the restaurant side.**

---

## 9. Files to Keep vs. Discard

### KEEP (canonical, working)
| File | Reason |
|---|---|
| `5th Gen Specific/5th gen with clustering...Final for 5th gen.py` | Canonical generator — fix and use |
| `5th Gen Specific/5th gen fundraising.py` | Better fundraising data — merge into main |
| `Serenity House Scripts/5th gen full sql generated script.sql` | Canonical OLTP schema |
| `SerenityPOC_DW/create Star schema.sql` | Canonical DW schema |
| `SerenityPOC_DW/SQL ETL into star schema.sql` | ETL logic |
| `Serenity House Scripts/5th generation *.sql` (validation queries) | Useful for QA |
| `SerenityPBI/DevopsTestSerenity/` | PBIP format — best for source control |
| `SerenityPBI/SerenityPOC2.pbix` | Working Power BI file |
| All `.docx` documents | Requirements/documentation source |

### DISCARD (superseded or junk)
| File | Reason |
|---|---|
| `4th gen with clustering*.py` | Superseded by 5th gen |
| `3rd gen create_drop schema.sql` | Superseded |
| `Second Generation*.sql` | Superseded |
| `4th gen actuallly has data.bak` / `...Pre150.bak` | Old database backups — archive or delete |
| `4th Gen Specific/` | Superseded |
| `SerenityPOC_DW/validate with copilot.txt` | Garbled Unicode, superseded |
| `SSIS/` | Not in scope for PoC |
| `SQLQuery1.sql`, `stays temp.sql` | Scratch files |
| `SerenityHousePlay.sqlite`, `SerenityHousePlay.sqbpro`, `copilot sqlite schema.txt` | Early SQLite prototype — discard |
| `DevartODBCSQLite.exe`, `sqliteodbc_w64.exe` | SQLite ODBC drivers — not needed |
| `5th Gen Specific/*try 1.py` | Draft, superseded by Final |
| Multiple `.pbix` variants (SerenityPOCPublic, SerenityPOCPublicTempTest, etc.) | Test/draft copies |

---

## 9. Proposed Clean Repo Structure

```
serenity-house-poc/
├── README.md
├── CHANGELOG.md
│
├── sql/
│   ├── oltp/
│   │   ├── 01_schema.sql          ← 5th gen full schema (fixed)
│   │   ├── 02_lookups.sql         ← seed data for lookup tables
│   │   └── 03_views.sql           ← vw_StayFinancialSummary, vw_InferredCluster, etc.
│   ├── dw/
│   │   ├── 01_star_schema.sql     ← DW table definitions
│   │   ├── 02_etl.sql             ← OLTP → DW ETL
│   │   └── 03_dim_date.sql        ← DimDate population
│   └── validation/
│       ├── core_validation.sql
│       ├── behavioral_validation.sql
│       └── financial_validation.sql
│
├── python/
│   ├── generate_data.py           ← merged 5th gen generator (residents + fundraising)
│   ├── config.py                  ← server, database, counts, dates
│   └── requirements.txt
│
├── powerbi/
│   └── SerenityPOC2.pbip/         ← PBIP project (source-controllable)
│       ├── SerenityPOC2.SemanticModel/
│       └── SerenityPOC2.Report/
│
├── docs/
│   ├── requirements-summary.md    ← this document
│   ├── data-dictionary.md
│   ├── architecture.md
│   └── behavioral-model.md
│
└── excel/
    └── (Phase 2 — Excel front-end files)
```

---

## 10. Open Questions Before We Build

1. **Restaurant component** — What does this look like? What data needs to be tracked?
2. **Cluster weights** — 50/25/25 (original docs) or 60/30/10 (final generator)? 
3. **StayRoomAssignments** — Do we need full room-move tracking in the PoC, or is single bed-per-stay sufficient for now?
4. **CaseNotes** — Do we want case notes in the PoC (they're in the ERD docs but not the current schema)?
5. **Number of residents** — Keep 150, or go larger?
6. **Date range** — Keep 2018–2026?
7. **Active residents** — How many should be "currently active" (ExitDate = NULL) vs. historical?
8. **SQL Server access** — Can you share the create scripts or a connection so we can validate the live schema?
9. **Excel front-end** — Which module first? Rent ledger, occupancy, donations entry?
10. **Architecture debate** — Are we staying with SQL Server + Power BI, or open to discussing alternatives?
