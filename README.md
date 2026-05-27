# Serenity House Analytics PoC

A full-stack analytics proof of concept built for **Serenity House**, a 45-bed nonprofit recovery residence in Clarksville, Indiana. The system demonstrates how a modern data pipeline — from synthetic data generation through a star-schema data warehouse to interactive Power BI dashboards — can replace manual spreadsheet reporting and give staff and leadership actionable, real-time insight into resident outcomes, finances, and program health.

This project is also a portfolio artifact demonstrating end-to-end data engineering and analytics skills across SQL Server, Python, DAX, and Power BI.

---

## What It Does

- **Tracks 500 synthetic residents** across 698 program stays spanning 2022–2029, with realistic behavioral clustering (Reliable 60% / Struggling 30% / Chronic 10%)
- **10+ interactive Power BI dashboard pages** covering occupancy, rent & arrears, demographics, referral sources, donations, funding assistance, behavior incidents, and resident drillthrough profiles
- **Early Warning dashboard** flagging at-risk current residents by incident rate, arrears trend, drug test results, and missed meetings — designed for weekly case manager review
- **Resident Profile drillthrough** — right-click any resident name anywhere in the report to drill through to their individual summary: days in program, arrears history, incident log, payment history
- **Reproducible rebuild** — five-step script sequence regenerates the entire database from scratch

---

## Tech Stack

| Layer | Technology |
|---|---|
| Data generation | Python (pyodbc, Faker, deterministic seed) |
| Operational schema | SQL Server (OLTP, `sh` schema, normalized) |
| Data warehouse | SQL Server (star schema, `dw` schema) |
| ETL | T-SQL |
| Semantic model | Power BI PBIP format (version-controlled TMDL) |
| Dashboards | Power BI Desktop, DAX measures |
| Version control | Git / GitHub |

---

## Architecture

```
Python Generator
      │
      ▼
SQL Server OLTP (sh schema)
  Residents, Stays, Beds, Rooms, Houses
  RentCharges, RentPayments, RentWaivers
  DrugTests, Incidents, EmploymentSnapshots
  ServiceEncounters, Donations, FinancialAssistance
      │
      ▼  (T-SQL ETL)
SQL Server Data Warehouse (dw schema — star schema)
  Dims: DimResident, DimBed, DimRoom, DimHouse, DimDate,
        DimIncidentType, DimReferralSource, DimDonor, DimFundraisingEvent
  Facts: FactStay, FactRentCharge, FactRentPayment, FactRentWaiver,
         FactIncident, FactDrugTest, FactDonation, FactFinancialAssistance
      │
      ▼
Power BI Semantic Model (PBIP / TMDL)
  DAX measures, calculated columns, inactive relationships + USERELATIONSHIP
      │
      ▼
Power BI Dashboards (10+ pages)
```

---

## Dashboard Pages

| Page | Description |
|---|---|
| Read First | Context for stakeholders — what this is, what it isn't, how to use it |
| Areas Served | Geographic origin of residents; referral source map |
| Rent | Weekly rent charges, collection rate, payment method breakdown |
| Arrears | Resident arrears balances, trend over time, residents in arrears count |
| Demographics | Age, gender, race/ethnicity breakdown of residents and program stays |
| Referrals | Intake volume by referral source category (court, treatment, self, etc.) |
| Donations | Donation totals, donor counts, recurring vs one-time, general fund vs events |
| Funding | Financial assistance by program type; residents assisted |
| Behaviors | Incident counts and trends, drug test results, positive test rate |
| Resident Profile | **Drillthrough** — per-resident summary (days in program, arrears, incidents, payments) |
| Early Warning | At-risk current residents flagged by incident rate, arrears trend, drug tests, missed meetings |

---

## Key Technical Features

### Synthetic Data Generator
- 500 residents, 698 stays, deterministic (`seed=42`)
- Behavioral clusters drive realistic distributions of incidents, arrears, and payment consistency
- Future-dated records (2026–2029) included intentionally — the report filters to `<= TODAY()` to simulate a live system

### Star Schema Design
- All date relationships from fact tables to `DimDate` are **inactive** — measures use `USERELATIONSHIP()` for date filtering, keeping the model clean and avoiding ambiguous relationship chains
- `FactStay` is the hub — all behavioral and financial fact tables link through `StayKey`

### DAX Patterns
- `Is Current Stay` calculated column on `FactStay` — powers occupancy and current resident filtering
- `Is Future Intake` calculated column — report-level filter excludes future residents from all pages, cascading through the entire model
- `Is Future Incident / Payment / Test` — visual-level filters for table visuals where integer date keys cannot use Power BI's native relative date filter
- Drillthrough context awareness — measures on the Resident Profile page are written to respect drillthrough filter context rather than clearing it with `ALLEXCEPT`

### PBIP / Version Control
- Report saved in **PBIP format** (Power BI Project) — semantic model stored as human-readable TMDL files, fully tracked in git
- Credentials and connection strings gitignored — never committed

---

## Setup & Rebuild

Prerequisites: SQL Server, Python 3.x, Power BI Desktop

```powershell
# 1. Create the schema
sqlcmd -S YOUR_SERVER -d YOUR_DB -i sql\00_drop_all.sql
sqlcmd -S YOUR_SERVER -d YOUR_DB -i sql\oltp\01_schema.sql
sqlcmd -S YOUR_SERVER -d YOUR_DB -i sql\dw\01_star_schema.sql

# 2. Generate synthetic data
cd python
pip install -r requirements.txt
python generate_data.py

# 3. Run ETL
sqlcmd -S YOUR_SERVER -d YOUR_DB -i sql\dw\02_etl.sql
```

Then open `powerbi/SerenityPOC2.pbip` in Power BI Desktop and refresh the dataset.

> **Note:** Update `python/config.py` (gitignored) with your SQL Server connection string before running the generator.

---

## What This Demonstrates

- End-to-end data pipeline design: OLTP → ETL → data warehouse → semantic model → dashboards
- SQL Server schema design — normalized operational model and star schema warehouse
- Python data engineering — deterministic synthetic data generation with behavioral clustering
- Power BI advanced patterns — inactive relationships, USERELATIONSHIP, drillthrough, calculated columns, DAX context management
- Version-controlled Power BI using PBIP/TMDL format
- Nonprofit analytics domain — resident outcomes, financial sustainability, program health metrics
- Stakeholder-focused design — built around real operational questions a program director would ask in weekly case manager reviews

---

## Production Path

This PoC intentionally omits production concerns. The intended production architecture replaces the Python generator with Excel-based data entry:

```
Excel (staff data entry) → Import/Transform → DW → Power BI
```

The OLTP schema serves as a **data model reference** — defining what fields need to be captured — rather than a live transactional system.

---

## License

MIT License — code and documentation are freely reusable.

---

## Contact

**Peter Smith**
[GitHub: peter-c-smith](https://github.com/peter-c-smith)
peterkodez@gmail.com
