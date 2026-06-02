# Azure Migration Guide
*Serenity House PoC — Local SQL Server → Azure SQL Database*

**Target:** `serenityhousepeter.database.windows.net` / `SerenityHouse`  
**Tier:** Free Serverless Gen5, 2 vCores, 32 GB — auto-pauses after inactivity

---

## Overview

The migration moves the Serenity House database from the local SQL Server instance (`PETRISLAP2025\PETRIS2022`) to Azure SQL Database. The schema and ETL scripts are fully compatible — Azure SQL Database supports the same T-SQL syntax. The Power BI semantic model now uses M query parameters (`ServerName` / `DatabaseName`) so switching targets requires changing two values in one place.

---

## Pre-Migration Checklist

- [ ] Azure SQL Database `SerenityHouse` exists on `serenityhousepeter.database.windows.net`
- [ ] SQL login created on Azure with `db_owner` or schema-level permissions (see Security section)
- [ ] Azure firewall rule allows your IP (`Set server firewall` in Azure portal)
- [ ] ODBC Driver 17 for SQL Server installed locally
- [ ] `python-dotenv` installed: `pip install python-dotenv --break-system-packages`

---

## Step 1: Set Up the .env File

Copy the template and fill in credentials:

```powershell
cd "D:\OneDrive\Serenity House\SerenityPOC Repo\python"
copy .env.example .env
notepad .env
```

Set these values in `.env`:

```env
SH_SERVER=serenityhousepeter.database.windows.net
SH_DATABASE=SerenityHouse
SH_AUTH=sql
SH_USER=your_azure_sql_username
SH_PASSWORD=your_azure_sql_password
```

> `.env` is gitignored — never committed. `.env.example` is the safe template that stays in git.

---

## Step 2: Create the Schema on Azure

The Azure DB starts empty. Run the schema scripts against it. Use sqlcmd with SQL auth (Azure SQL doesn't support Windows auth from a local machine):

```powershell
$server   = "serenityhousepeter.database.windows.net"
$database = "SerenityHouse"
$user     = "your_username"
$password = "your_password"

sqlcmd -S $server -d $database -U $user -P $password -i sql\00_drop_all.sql
sqlcmd -S $server -d $database -U $user -P $password -i sql\oltp\01_schema.sql
sqlcmd -S $server -d $database -U $user -P $password -i sql\dw\01_star_schema.sql
```

Or use `rebuild.py` — it reads from `.env` automatically:

```powershell
cd python
python rebuild.py
```

---

## Step 3: Generate Data to Azure

With `.env` configured for Azure, the generator connects directly to Azure SQL:

```powershell
cd python
python generate_data.py
```

Progress streams live as normal. The generator will take slightly longer than local due to network latency on each batch insert (~5–8 min vs ~2–3 min locally).

---

## Step 4: Run ETL

```powershell
sqlcmd -S serenityhousepeter.database.windows.net -d SerenityHouse -U $user -P $password -i sql\dw\02_etl.sql
```

Or let `rebuild.py` handle it as part of the full rebuild.

---

## Step 5: Update Power BI

The semantic model uses M query parameters — switching to Azure is a two-value change.

**In Power BI Desktop:**

1. Open `powerbi/SerenityPOC2.pbip`
2. Home → Transform data → Edit parameters
3. Set `ServerName` = `serenityhousepeter.database.windows.net`
4. Set `DatabaseName` = `SerenityHouse`
5. Click OK → Apply changes
6. Enter credentials when prompted (select **Database** auth, enter SQL username/password)
7. Refresh the dataset to verify

**Alternatively** (via TMDL — Power BI must be closed):

Edit `powerbi/SerenityPOC2.SemanticModel/definition/expressions.tmdl`:

```
expression ServerName
    = "serenityhousepeter.database.windows.net" meta [IsParameterQuery=true, ...]

expression DatabaseName
    = "SerenityHouse" meta [IsParameterQuery=true, ...]
```

These are already set to Azure values. To revert to local, change them back to `PETRISLAP2025\PETRIS2022` / `Serenity1`.

---

## Step 6: Verify

```sql
-- Run in Azure Query Editor (portal) or SSMS connected to Azure
SELECT 'FactStay'     AS TableName, COUNT(*) AS Rows FROM dw.FactStay
SELECT 'DimResident'  AS TableName, COUNT(*) AS Rows FROM dw.DimResident
SELECT 'FactIncident' AS TableName, COUNT(*) AS Rows FROM dw.FactIncident

-- Active residents today
SELECT COUNT(*) AS ActiveToday
FROM dw.FactStay
WHERE IntakeDateKey <= CAST(FORMAT(GETDATE(),'yyyyMMdd') AS INT)
  AND ExitDateKey   >= CAST(FORMAT(GETDATE(),'yyyyMMdd') AS INT)
```

Expected: ~700 stays, ~500 residents, ~28 active today.

---

## Security

### Azure SQL Login

Create a dedicated SQL login on Azure (not admin). In Azure Query Editor or SSMS:

```sql
-- Run as admin on master database
CREATE LOGIN serenity_app WITH PASSWORD = 'StrongPassword123!';

-- Run on SerenityHouse database
CREATE USER serenity_app FOR LOGIN serenity_app;
ALTER ROLE db_datareader ADD MEMBER serenity_app;   -- read-only for Power BI
ALTER ROLE db_datawriter ADD MEMBER serenity_app;   -- write access for generator/ETL
-- Or grant full: ALTER ROLE db_owner ADD MEMBER serenity_app;
```

### Firewall Rules

Azure SQL blocks all connections by default. Add your IP:

- Azure Portal → SerenityHouse SQL server → Networking → Add client IP → Save
- For Power BI Service (cloud refresh): enable **Allow Azure services and resources to access this server**

### Credential Storage

| Location | How credentials are stored |
|---|---|
| Python scripts | `.env` file (gitignored), read via `python-dotenv` |
| Power BI Desktop | Windows Credential Manager (entered once on first connect) |
| Power BI Service | Gateway or cloud data source credentials (configured in Service) |
| sqlcmd | `-U` / `-P` flags or environment variables |

**Never** commit `.env` or put passwords in SQL scripts.

---

## Serverless Tier — Important Notes

The Azure database is on the **Free Serverless** tier. This has two implications:

**Auto-pause:** The database pauses automatically after ~1 hour of inactivity. The first query after a pause takes 20–60 seconds to "warm up" (cold start). This is normal — Power BI will show a connection delay on first refresh after the DB has been idle.

**vCore seconds:** The free tier includes 100,000 vCore seconds/month. At 2 vCores, that's ~13.9 hours of active compute per month. For a demo/PoC with infrequent access this is more than enough. Monitor usage in the Azure portal if concerned.

**Auto-pause workaround for demos:** Run a simple query against the DB a minute before a presentation to warm it up:
```powershell
sqlcmd -S serenityhousepeter.database.windows.net -d SerenityHouse -U $user -P $password -Q "SELECT 1"
```

---

## Switching Back to Local

To point everything back at the local SQL Server:

**Python:** Edit `python/.env`:
```env
SH_SERVER=PETRISLAP2025\PETRIS2022
SH_DATABASE=Serenity1
SH_AUTH=windows
```

**Power BI:** Edit parameters (Transform data → Edit parameters) or update `expressions.tmdl` directly.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| Cannot open server ... firewall | Client IP not whitelisted | Add IP in Azure portal → Networking |
| Login failed for user | Wrong credentials or user doesn't exist | Verify SQL login in Azure Query Editor |
| Cannot connect to server (timeout) | DB is paused (cold start) | Wait 30–60 sec and retry |
| SSL/TLS error in pyodbc | Old ODBC driver | Install ODBC Driver 17 or 18 |
| Power BI "datasource not found" | Parameters not applied | Transform data → Edit parameters → Apply |
