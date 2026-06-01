"""
Serenity House PoC — One-Command Rebuild Script
=================================================
Drops and rebuilds the entire database, then regenerates all synthetic data.

Usage:
    python rebuild.py

Requires:
    - sqlcmd on PATH  (ships with SQL Server tools)
    - pyodbc, faker   (pip install pyodbc faker)
    - ODBC Driver 17 for SQL Server

Steps:
    1. sql/00_drop_all.sql         — drop all sh/dw objects
    2. sql/oltp/01_schema.sql      — recreate OLTP (sh) schema
    3. sql/dw/01_star_schema.sql   — recreate DW (dw) star schema
    4. python/generate_data.py     — generate synthetic data (v7, streamed output)
    5. sql/dw/02_etl.sql           — run ETL from sh → dw
"""

import subprocess
import sys
import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SERVER   = r"PETRISLAP2025\PETRIS2022"
DATABASE = "Serenity1"

# Resolve paths relative to this script's location
REPO_ROOT = Path(__file__).resolve().parent.parent   # SerenityPOC Repo/
SQL_DIR   = REPO_ROOT / "sql"
PY_DIR    = REPO_ROOT / "python"

SQL_STEPS = [
    ("Drop all objects",      SQL_DIR / "00_drop_all.sql"),
    ("Create OLTP schema",    SQL_DIR / "oltp" / "01_schema.sql"),
    ("Create DW star schema", SQL_DIR / "dw"   / "01_star_schema.sql"),
    ("Run ETL",               SQL_DIR / "dw"   / "02_etl.sql"),
]

GENERATOR = PY_DIR / "generate_data.py"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def banner(title: str):
    print()
    print("=" * 60)
    print(f"  {title}")
    print("=" * 60)


def run_sql(label: str, script: Path):
    """Run a SQL script via sqlcmd, streaming output live."""
    banner(label)
    if not script.exists():
        print(f"ERROR: Script not found: {script}")
        sys.exit(1)

    cmd = [
        "sqlcmd",
        "-S", SERVER,
        "-d", DATABASE,
        "-E",                  # Windows auth (Trusted Connection)
        "-i", str(script),
        "-b",                  # exit with error code on SQL error
    ]

    result = subprocess.run(cmd, text=True)
    if result.returncode != 0:
        print(f"\nERROR: sqlcmd exited with code {result.returncode}")
        sys.exit(result.returncode)
    print(f"  ✓ {label} complete")


def run_generator():
    """Run generate_data.py with live-streamed output."""
    banner("Generate synthetic data (v7)")
    if not GENERATOR.exists():
        print(f"ERROR: Generator not found: {GENERATOR}")
        sys.exit(1)

    # Use the same Python interpreter that's running this script
    cmd = [sys.executable, str(GENERATOR)]

    # Stream stdout and stderr live — user sees progress as it happens
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,          # line-buffered
        cwd=str(PY_DIR),
    )

    for line in process.stdout:
        print(line, end="", flush=True)

    process.wait()
    if process.returncode != 0:
        print(f"\nERROR: Generator exited with code {process.returncode}")
        sys.exit(process.returncode)
    print("  ✓ Data generation complete")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    banner("Serenity House PoC — Full Rebuild")
    print(f"  Server:   {SERVER}")
    print(f"  Database: {DATABASE}")
    print(f"  Repo:     {REPO_ROOT}")

    # Confirm before destroying the database
    print()
    confirm = input("  This will DROP and REBUILD all data. Continue? [y/N] ").strip().lower()
    if confirm != "y":
        print("  Aborted.")
        sys.exit(0)

    # Steps 1–3: SQL setup
    for label, script in SQL_STEPS[:3]:
        run_sql(label, script)

    # Step 4: Python generator (streamed)
    run_generator()

    # Step 5: ETL
    run_sql(*SQL_STEPS[3])

    banner("Rebuild complete!")
    print("  Next: refresh Power BI to pick up the new data.")
    print()


if __name__ == "__main__":
    main()
