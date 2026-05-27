"""
Serenity House PoC — Synthetic Data Generator (v6)
====================================================
Generates realistic synthetic data for the Serenity House analytics PoC.

Usage:
    python generate_data.py

Requirements:
    pip install pyodbc faker --break-system-packages   (or: pip install pyodbc faker)

Architecture:
    Writes directly to SQL Server via pyodbc (Trusted Connection / Windows Auth).
    Later: port to SQLite by swapping the Connection class at the bottom.

Occupancy Model (seasonal, deterministic):
    Winter (Nov–Feb): 90–100% — peaks at 45/45 beds for 1–2 months straight
    Fall   (Sep–Oct): 78–87%
    Summer (Jun–Aug): 68–80%
    Spring (Mar–May): 55–70% — peak departure season

Behavioral Clusters (in-memory only — never stored):
    Reliable  60%: rent payment rate 95%, drug positive 5%,  incidents 0–1
    Struggling 30%: rent payment rate 60%, drug positive 20%, incidents 0–3
    Chronic   10%: rent payment rate 10%, drug positive 40%, incidents 1–6

Identity Masking:
    SecurityIdentityMap stores a UUID per resident.
    External reports use PublicResidentID, never ResidentID.
"""

import random
import uuid
import math
from datetime import date, timedelta, datetime
from decimal import Decimal

import pyodbc
from faker import Faker

# ===========================================================================
# CONFIG — edit these to match your environment
# ===========================================================================
SERVER       = r"PETRISLAP2025\PETRIS2022"
DATABASE     = "Serenity1"
CONN_STRING  = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};"
    f"DATABASE={DATABASE};"
    "Trusted_Connection=yes;"
)

SEED              = 42           # Reproducible results
NUM_RESIDENTS  = 500
NUM_CASE_MANAGERS = 6
NUM_HOUSES        = 1            # One house: Serenity House
ROOMS_PER_HOUSE   = 15
BEDS_PER_ROOM     = 3            # 15 × 3 = 45 beds total
TOTAL_BEDS        = ROOMS_PER_HOUSE * BEDS_PER_ROOM

WEEKLY_RENT       = Decimal("105.00")

START_DATE = date(2022, 1, 1)
END_DATE      = date(2029, 12, 31)   # Scheduling boundary for stay generation
ACTIVE_EXPIRY = date(2027, 12, 31)   # ⚠️ ExitDate for all currently active stays.
                                      # Dashboard "current resident" logic breaks after this date.
                                      # Regenerate the dataset before 2027-12-31 if PoC still in use.

# Fundraising scale
NUM_DONORS      = 300
NUM_EVENTS      = 20
NUM_DONATIONS   = 2500

# Cluster weights
CLUSTER_WEIGHTS = [0.60, 0.30, 0.10]   # Reliable, Struggling, Chronic

# ===========================================================================
# SETUP
# ===========================================================================
fake = Faker("en_US")
Faker.seed(SEED)
random.seed(SEED)

TODAY = date.today()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def daterange(start: date, end: date):
    """Yield each date from start to end (exclusive)."""
    cur = start
    while cur < end:
        yield cur
        cur += timedelta(days=1)


def weighted_choice(items, weights):
    r = random.random()
    cumulative = 0.0
    for item, w in zip(items, weights):
        cumulative += w
        if r < cumulative:
            return item
    return items[-1]


def seasonal_occupancy_target(d: date) -> float:
    """Return a target occupancy fraction for the given date."""
    m = d.month
    # Winter: Nov–Feb — very high demand
    if m in (11, 12, 1, 2):
        # Occasionally hit 100% for multi-week stretches
        week_of_year = d.timetuple().tm_yday // 7
        if (week_of_year % 8) < 3:   # ~37% of winter weeks at max
            return 1.00
        return random.uniform(0.90, 0.99)
    # Spring: Mar–May — departure season
    elif m in (3, 4, 5):
        return random.uniform(0.55, 0.70)
    # Summer: Jun–Aug
    elif m in (6, 7, 8):
        return random.uniform(0.68, 0.80)
    # Fall: Sep–Oct
    else:
        return random.uniform(0.78, 0.87)


def cluster_for_resident(idx: int) -> str:
    """Assign behavioral cluster deterministically by resident index."""
    r = (idx * 6364136223846793005 + 1442695040888963407) % (2**32) / (2**32)
    if r < CLUSTER_WEIGHTS[0]:
        return "Reliable"
    elif r < CLUSTER_WEIGHTS[0] + CLUSTER_WEIGHTS[1]:
        return "Struggling"
    return "Chronic"


# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

class Connection:
    """Thin wrapper around pyodbc — swap this class for SQLite later."""

    def __init__(self):
        self.conn = pyodbc.connect(CONN_STRING, autocommit=False)
        self.cur  = self.conn.cursor()

    def execute(self, sql, params=()):
        self.cur.execute(sql, params)

    def executemany(self, sql, rows):
        self.cur.executemany(sql, rows)

    def fetchone(self):
        return self.cur.fetchone()

    def fetchall(self):
        return self.cur.fetchall()

    def commit(self):
        self.conn.commit()

    def rollback(self):
        self.conn.rollback()

    def close(self):
        self.cur.close()
        self.conn.close()

    def insert_one(self, sql, params=()):
        """Execute an INSERT ... OUTPUT INSERTED.* and return the first column of result."""
        self.cur.execute(sql, params)
        row = self.cur.fetchone()
        return row[0] if row else None


# ===========================================================================
# GENERATORS
# ===========================================================================

def generate_house_room_beds(db: Connection):
    """Create the single Serenity House with 15 rooms × 3 beds."""
    print("  Creating house, rooms, beds...")

    house_id = db.insert_one(
        """INSERT INTO sh.House (HouseName, Address, City, StateCode, ZipCode, TotalBeds)
           OUTPUT INSERTED.HouseID
           VALUES (?,?,?,?,?,?)""",
        ("Serenity House", "123 Recovery Lane", "Springfield", "IL", "62701", TOTAL_BEDS)
    )
    db.commit()

    room_ids = []
    for r in range(1, ROOMS_PER_HOUSE + 1):
        room_number = f"{r:03d}"
        room_id = db.insert_one(
            """INSERT INTO sh.Room (HouseID, RoomNumber, BedsInRoom)
               OUTPUT INSERTED.RoomID VALUES (?,?,?)""",
            (house_id, room_number, BEDS_PER_ROOM)
        )
        room_ids.append(room_id)

    db.commit()

    bed_ids = []
    for room_id in room_ids:
        for label in ("A", "B", "C"):
            bed_id = db.insert_one(
                """INSERT INTO sh.Bed (RoomID, BedLabel)
                   OUTPUT INSERTED.BedID VALUES (?,?)""",
                (room_id, label)
            )
            bed_ids.append(bed_id)

    db.commit()
    print(f"    House {house_id}: {len(room_ids)} rooms, {len(bed_ids)} beds")
    return house_id, room_ids, bed_ids


def generate_case_managers(db: Connection):
    print("  Creating case managers...")
    manager_ids = []
    for _ in range(NUM_CASE_MANAGERS):
        mgr_id = db.insert_one(
            """INSERT INTO sh.CaseManager (FirstName, LastName, Email, HiredDate)
               OUTPUT INSERTED.CaseManagerID VALUES (?,?,?,?)""",
            (fake.first_name(), fake.last_name(),
             fake.email(), fake.date_between(START_DATE, date(2022, 6, 1)))
        )
        manager_ids.append(mgr_id)
    db.commit()
    print(f"    {len(manager_ids)} case managers created")
    return manager_ids


def generate_residents(db: Connection):
    """Generate NUM_RESIDENTS synthetic residents with identity masking."""
    print(f"  Creating {NUM_RESIDENTS} residents...")

    GENDERS    = ["Male", "Female", "Non-binary", "Other"]
    G_WEIGHTS  = [0.70, 0.25, 0.03, 0.02]
    RACES      = ["White", "Black or African American", "Hispanic or Latino",
                  "Asian", "American Indian", "Two or More Races", "Unknown"]
    R_WEIGHTS  = [0.42, 0.28, 0.18, 0.04, 0.03, 0.03, 0.02]
    SUBSTANCES = ["Alcohol", "Opioids", "Methamphetamine", "Cocaine",
                  "Cannabis", "Heroin", "Multiple", "Other"]
    S_WEIGHTS  = [0.30, 0.25, 0.18, 0.10, 0.07, 0.05, 0.04, 0.01]
    EDUCATION  = ["Less than High School", "High School / GED",
                  "Some College", "Associate's Degree", "Bachelor's Degree", "Graduate Degree"]
    E_WEIGHTS  = [0.15, 0.38, 0.25, 0.10, 0.10, 0.02]
    REL_TYPES  = ["Mother", "Father", "Spouse", "Sibling", "Friend", "Child", "Other"]

    # Shared location pool — real cities in the service area.
    # Used for BOTH origin (where resident came from) and home address.
    # Weights target: ~65% Indiana, ~25% Kentucky, ~10% other states.
    # NOTE: weights are normalized to sum=1 before use so weighted_choice works correctly.
    LOCATION_POOL = [
        # (City, State, County, weight)
        # Clark County, IN — primary catchment
        ("Clarksville",      "IN", "Clark County",         10.0),
        ("Jeffersonville",   "IN", "Clark County",          9.0),
        ("Charlestown",      "IN", "Clark County",          5.0),
        ("Sellersburg",      "IN", "Clark County",          3.5),
        # Floyd County, IN
        ("New Albany",       "IN", "Floyd County",          7.0),
        ("Georgetown",       "IN", "Floyd County",          2.5),
        ("Floyds Knobs",     "IN", "Floyd County",          2.0),
        # Harrison County, IN
        ("Corydon",          "IN", "Harrison County",       3.0),
        ("Elizabeth",        "IN", "Harrison County",       1.0),
        # Scott County, IN
        ("Scottsburg",       "IN", "Scott County",          2.0),
        ("Austin",           "IN", "Scott County",          2.0),
        # Washington County, IN
        ("Salem",            "IN", "Washington County",     2.0),
        # Jefferson County, IN
        ("Madison",          "IN", "Jefferson County",      1.5),
        # Jackson County, IN
        ("Seymour",          "IN", "Jackson County",        1.5),
        # Bartholomew County, IN
        ("Columbus",         "IN", "Bartholomew County",    1.0),
        # Monroe County, IN
        ("Bloomington",      "IN", "Monroe County",         2.0),
        # Marion County, IN
        ("Indianapolis",     "IN", "Marion County",         3.0),
        # Vanderburgh County, IN
        ("Evansville",       "IN", "Vanderburgh County",    1.0),
        # Jefferson County, KY — Louisville metro
        ("Louisville",       "KY", "Jefferson County",     12.0),
        # Oldham County, KY
        ("La Grange",        "KY", "Oldham County",         2.5),
        # Bullitt County, KY
        ("Shepherdsville",   "KY", "Bullitt County",        2.5),
        # Shelby County, KY
        ("Shelbyville",      "KY", "Shelby County",         2.0),
        # Hardin County, KY
        ("Elizabethtown",    "KY", "Hardin County",         2.0),
        # Fayette County, KY
        ("Lexington",        "KY", "Fayette County",        2.0),
        # Out-of-area
        ("Cincinnati",       "OH", "Hamilton County",       3.5),
        ("Nashville",        "TN", "Davidson County",       2.0),
        ("Chicago",          "IL", "Cook County",           2.0),
        ("Dayton",           "OH", "Montgomery County",     1.5),
    ]
    _pool_items = [(c, s, co) for c, s, co, _ in LOCATION_POOL]
    _raw_w      = [w for _, _, _, w in LOCATION_POOL]
    _total_w    = sum(_raw_w)
    _pool_weights = [w / _total_w for w in _raw_w]   # normalized → sum = 1.0

    resident_ids = []
    clusters = []

    for i in range(NUM_RESIDENTS):
        cluster = cluster_for_resident(i)
        clusters.append(cluster)

        gender = weighted_choice(GENDERS, G_WEIGHTS)
        if gender == "Male":
            fname = fake.first_name_male()
        elif gender == "Female":
            fname = fake.first_name_female()
        else:
            fname = fake.first_name()

        dob = fake.date_of_birth(minimum_age=18, maximum_age=65)
        substance_start_age = random.randint(12, 25)

        # Origin: where the resident came from
        origin_city, origin_state, origin_county = weighted_choice(_pool_items, _pool_weights)
        # Home address: 80% same city as origin, 20% a different draw from same pool
        if random.random() < 0.80:
            home_city, home_state = origin_city, origin_state
        else:
            home_loc = weighted_choice(_pool_items, _pool_weights)
            home_city, home_state = home_loc[0], home_loc[1]

        pid = db.insert_one(
            """INSERT INTO sh.Resident
               (FirstName, LastName, DateOfBirth, Gender, Race, Ethnicity,
                MaritalStatus, EducationLevel, Phone, Email,
                HomeCity, HomeState,
                OriginCity, OriginState, OriginCounty,
                EmergencyContactName, EmergencyContactPhone, EmergencyContactRel,
                NationalID, AlternateID,
                PrimarySubstance, SubstanceUseStartAge, PriorTreatmentCount)
               OUTPUT INSERTED.ResidentID
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                fname,
                fake.last_name(),
                dob,
                gender,
                weighted_choice(RACES, R_WEIGHTS),
                "Hispanic or Latino" if random.random() < 0.18 else "Not Hispanic or Latino",
                random.choice(["Single", "Married", "Divorced", "Widowed", "Separated"]),
                weighted_choice(EDUCATION, E_WEIGHTS),
                fake.numerify("(###) ###-####"),
                fake.email() if random.random() < 0.6 else None,
                home_city,
                home_state,
                origin_city, origin_state, origin_county,
                fake.name(),
                fake.numerify("(###) ###-####"),
                random.choice(REL_TYPES),
                f"NID-{fake.numerify('######')}",
                f"ALT-{fake.numerify('######')}",
                weighted_choice(SUBSTANCES, S_WEIGHTS),
                substance_start_age,
                random.randint(0, 5),
            )
        )
        resident_ids.append(pid)

        # Identity masking record
        db.execute(
            """INSERT INTO sh.SecurityIdentityMap (ResidentID, PublicResidentID)
               VALUES (?, ?)""",
            (pid, str(uuid.uuid4()))
        )

    db.commit()
    print(f"    {len(resident_ids)} residents + identity map records created")
    return resident_ids, clusters


def generate_stays(db: Connection, resident_ids, clusters,
                   bed_ids, case_manager_ids, referral_source_ids):
    """
    Generate stays with a seasonal occupancy model.

    Strategy:
    - Maintain a 'bed calendar': for each bed, track when it becomes free.
    - For each week from START_DATE to END_DATE, compute target occupancy.
    - Fill / drain beds by starting or not-starting new stays.
    - Residents can have multiple stays (with gaps between them).
    - Stays ending after TODAY get ExitDate in the future (representing active residents).
    """
    print("  Generating stays (seasonal occupancy model)...")

    # Track next-available date per bed
    bed_free: dict[int, date] = {bid: START_DATE for bid in bed_ids}
    # Track all stays created: list of (StayID, StayStatus, IntakeDate, ExitDate, BedID, ResidentID, cluster)
    all_stays = []

    # Pool of residents not currently in a stay
    resident_last_exit: dict[int, date] = {pid: START_DATE for pid in resident_ids}

    # Repeat stay constraints:
    #   - Max 4 stays per resident
    #   - ~25% of residents should have more than 1 stay (enforced naturally by
    #     90-day min gap + large resident pool — new residents preferred over returnees)
    MAX_STAYS_PER_RESIDENT = 4
    resident_stay_count: dict[int, int] = {pid: 0 for pid in resident_ids}

    # Weights must match order of sh.ReferralSource seed data (16 sources):
    # Jail, Prison, Drug Court, Probation/Parole,
    # Avenues, Sunrise, Hickory, Centerstone, True Healing, Life Springs, Hospital,
    # Street, Self-Referral, Family/Friend, Other
    REFERRAL_WEIGHTS = [
        0.18,  # Jail
        0.10,  # Prison
        0.08,  # Drug Court
        0.08,  # Probation / Parole
        0.10,  # Avenues
        0.08,  # Sunrise
        0.07,  # Hickory
        0.07,  # Centerstone
        0.05,  # True Healing
        0.05,  # Life Springs
        0.04,  # Hospital
        0.04,  # Street
        0.03,  # Self-Referral
        0.02,  # Family / Friend
        0.01,  # Other
    ]
    # Note: weights sum to 1.0 — required for weighted_choice()

    EXIT_REASONS = {
        "Completed": "Successfully completed program",
        "Terminated": None,  # will pick randomly
        "Transferred": "Transferred to another facility",
    }
    TERMINATION_REASONS = [
        "Positive drug test", "Curfew violation", "Non-payment of rent",
        "Behavioral issues", "Left against advice", "Incarceration",
        "Unknown / AWOL",
    ]

    def pick_length_of_stay(cluster: str) -> int:
        """Return length of stay in days based on cluster.
        Target weighted average ~5 months across all clusters (60/30/10 split):
          Reliable:  ~6 months × 60% = 3.6
          Struggling: ~4 months × 30% = 1.2
          Chronic:   ~2 months × 10% = 0.2
          Weighted average: ~5 months
        """
        if cluster == "Reliable":
            return int(random.gauss(180, 45))   # ~6 months average
        elif cluster == "Struggling":
            return int(random.gauss(120, 45))   # ~4 months
        else:
            return int(random.gauss(60, 30))    # ~2 months (higher churn)

    def pick_exit_type(cluster: str):
        if cluster == "Reliable":
            r = random.random()
            if r < 0.75:    return "Completed"
            elif r < 0.90:  return "Terminated"
            else:           return "Transferred"
        elif cluster == "Struggling":
            r = random.random()
            if r < 0.45:    return "Completed"
            elif r < 0.85:  return "Terminated"
            else:           return "Transferred"
        else:  # Chronic
            r = random.random()
            if r < 0.15:    return "Completed"
            elif r < 0.90:  return "Terminated"
            else:           return "Transferred"

    # Walk through the dataset month by month to manage occupancy
    current = START_DATE
    while current <= END_DATE:
        target_occ = seasonal_occupancy_target(current)
        target_beds = max(23, min(TOTAL_BEDS, int(target_occ * TOTAL_BEDS)))

        # Count currently occupied beds
        occupied = sum(1 for bid, free in bed_free.items() if free > current)

        # Start new stays if we're below target
        deficit = target_beds - occupied
        if deficit > 0:
            # Find available beds
            available_beds = [bid for bid, free in bed_free.items() if free <= current]
            random.shuffle(available_beds)

            # Find available residents (those who have been out long enough)
            # 90-day min gap between stays + large pool naturally keeps ~25% repeat rate
            min_gap = 90  # at least 3 months between stays
            available_residents = [
                (pid, clusters[resident_ids.index(pid)])
                for pid in resident_ids
                if resident_stay_count[pid] < MAX_STAYS_PER_RESIDENT  # max 4 stays
                and resident_last_exit[pid] + timedelta(days=min_gap) <= current
                and bed_free.get(  # not currently assigned
                    next((s[4] for s in all_stays
                          if s[5] == pid and s[3] is not None and s[3] > current), None), date.min
                ) <= current
            ]
            # Prefer residents who haven't had a stay yet — keeps repeat rate ~25%
            available_residents.sort(key=lambda x: resident_stay_count[x[0]])
            # Shuffle within same stay-count groups to avoid alphabetical bias
            first_timers = [r for r in available_residents if resident_stay_count[r[0]] == 0]
            returnees    = [r for r in available_residents if resident_stay_count[r[0]] > 0]
            random.shuffle(first_timers)
            random.shuffle(returnees)
            available_residents = first_timers + returnees

            for bed_id, (pid, cluster) in zip(available_beds[:deficit], available_residents[:deficit]):
                los = max(14, min(730, pick_length_of_stay(cluster)))
                intake = current + timedelta(days=random.randint(0, 6))
                exit_d = intake + timedelta(days=los)

                if exit_d > END_DATE:
                    exit_d = END_DATE

                status = "Active" if (intake <= TODAY and exit_d > TODAY) else pick_exit_type(cluster)
                if status == "Active":
                    # Keep realistic varied exit dates but cap at ACTIVE_EXPIRY so the
                    # dataset doesn't break as time moves forward past 2027-12-31.
                    actual_exit = min(exit_d, ACTIVE_EXPIRY)
                else:
                    actual_exit = exit_d

                if status == "Terminated":
                    exit_reason = random.choice(TERMINATION_REASONS)
                elif status == "Transferred":
                    exit_reason = EXIT_REASONS["Transferred"]
                elif status == "Completed":
                    exit_reason = EXIT_REASONS["Completed"]
                else:
                    exit_reason = None

                ref_id = weighted_choice(referral_source_ids, REFERRAL_WEIGHTS)
                cm_id  = random.choice(case_manager_ids)

                stay_id = db.insert_one(
                    """INSERT INTO sh.Stay
                       (ResidentID, BedID, CaseManagerID, ReferralSourceID,
                        IntakeDate, ExitDate, StayStatus, ExitReason,
                        MeetingRequirement, BehavioralCluster)
                       OUTPUT INSERTED.StayID
                       VALUES (?,?,?,?,?,?,?,?,?,?)""",
                    (pid, bed_id, cm_id, ref_id,
                     intake, actual_exit, status, exit_reason,
                     "Phase1", cluster)
                )

                bed_free[bed_id] = exit_d + timedelta(days=1)        # use projected date for scheduling
                resident_last_exit[pid] = exit_d                     # use projected date for scheduling
                resident_stay_count[pid] += 1                        # track repeat stays (max 4)
                all_stays.append((stay_id, status, intake, actual_exit,
                                   bed_id, pid, cluster, cm_id))

        # Advance by one week
        current += timedelta(days=7)

    db.commit()
    print(f"    {len(all_stays)} stays created")
    return all_stays


def generate_drug_tests(db: Connection, all_stays):
    """Random drug tests — frequency and positive rate depend on cluster."""
    print("  Generating drug tests...")

    CLUSTER_POS_RATE = {"Reliable": 0.05, "Struggling": 0.20, "Chronic": 0.40}
    SUBSTANCES = ["Methamphetamine", "Cocaine", "Heroin", "Opioids",
                  "Benzodiazepines", "THC", "Alcohol", "Multiple"]

    rows = []
    for stay_id, status, intake, exit_d, bed_id, pid, cluster, cm_id in all_stays:
        effective_exit = exit_d if exit_d is not None else TODAY
        stay_days = (effective_exit - intake).days
        # Roughly one test per 2 weeks, minimum 1
        n_tests = max(1, stay_days // 14)

        pos_rate = CLUSTER_POS_RATE[cluster]

        for _ in range(n_tests):
            test_date = intake + timedelta(days=random.randint(0, max(0, stay_days - 1)))
            result = "Positive" if random.random() < pos_rate else "Negative"
            if result == "Positive" and random.random() < 0.03:
                result = "Refused"

            substances = random.choice(SUBSTANCES) if result == "Positive" else None

            rows.append((stay_id, test_date, "Urine", result, substances, 1))

        if len(rows) >= 500:
            db.executemany(
                """INSERT INTO sh.DrugTest
                   (StayID, TestDate, TestType, Result, SubstancesDetected, IsRandom)
                   VALUES (?,?,?,?,?,?)""",
                rows
            )
            db.commit()
            rows = []

    if rows:
        db.executemany(
            """INSERT INTO sh.DrugTest
               (StayID, TestDate, TestType, Result, SubstancesDetected, IsRandom)
               VALUES (?,?,?,?,?,?)""",
            rows
        )
        db.commit()
    print(f"    Drug tests complete")


def generate_incidents(db: Connection, all_stays, incident_type_ids_by_name):
    """
    Generate incidents including meeting non-compliance, curfew violations,
    drug tests, employment non-compliance, etc.
    """
    print("  Generating incidents...")

    # Incident count distribution per stay by cluster.
    # Uses weighted sampling to produce a realistic skewed distribution:
    #   - Most Reliable residents have 0 incidents (clean record)
    #   - Struggling residents usually have a few, occasionally many
    #   - Chronic residents always have incidents, some leading to discharge
    # 60% of Reliable get 0, 40% get 1-3
    # 20% of Struggling get 0, 80% get 1-8
    # Chronic always get 3-20 (shorter stays already modeled in generator)
    def pick_incident_count(cluster: str) -> int:
        if cluster == "Reliable":
            return 0 if random.random() < 0.60 else random.randint(1, 3)
        elif cluster == "Struggling":
            return 0 if random.random() < 0.20 else random.randint(1, 8)
        else:  # Chronic
            return random.randint(3, 20)

    # Map incident type names to IDs
    meeting_type_id      = incident_type_ids_by_name.get("Incomplete Weekly Meetings")
    curfew_type_id       = incident_type_ids_by_name.get("Curfew Violation")
    drug_type_id         = incident_type_ids_by_name.get("Positive Drug Test")
    alcohol_type_id      = incident_type_ids_by_name.get("Positive Alcohol Test")
    employment_type_id   = incident_type_ids_by_name.get("Employment Non-Compliance")
    behavioral_type_id   = incident_type_ids_by_name.get("Disruptive Behavior")
    house_rule_id        = incident_type_ids_by_name.get("House Rule Violation")
    chore_type_id        = incident_type_ids_by_name.get("Chore Non-Compliance")
    other_type_id        = incident_type_ids_by_name.get("Other")

    common_types = [curfew_type_id, meeting_type_id, house_rule_id,
                    chore_type_id, behavioral_type_id, other_type_id]
    common_types = [t for t in common_types if t]

    ACTIONS = ["Verbal Warning", "Written Warning", "Formal Warning",
               "Probation", "Corrective Action Plan", "Discharge"]
    SEVERITY_ACTIONS = {
        "Low":      ACTIONS[:3],
        "Medium":   ACTIONS[1:5],
        "High":     ACTIONS[3:],
        "Critical": ACTIONS[4:],
    }

    rows = []
    for stay_id, status, intake, exit_d, bed_id, pid, cluster, cm_id in all_stays:
        effective_exit = exit_d if exit_d is not None else TODAY
        stay_days = (effective_exit - intake).days
        n_incidents = pick_incident_count(cluster)

        for _ in range(n_incidents):
            inc_date = intake + timedelta(days=random.randint(0, max(0, stay_days - 1)))
            inc_type_id = random.choice(common_types)
            action = random.choice(ACTIONS[:4])
            follow_up = random.random() < 0.3

            rows.append((stay_id, inc_type_id, inc_date,
                         "Documented per house policy",
                         action, int(follow_up), None, None, "Staff"))

        # Employment non-compliance for Chronic cluster (25% chance)
        if cluster == "Chronic" and employment_type_id and random.random() < 0.25:
            emp_date = intake + timedelta(days=random.randint(16, 45))
            effective_exit = exit_d if exit_d is not None else TODAY
            if emp_date < effective_exit:
                rows.append((stay_id, employment_type_id, emp_date,
                             "Failed to obtain employment within 15-day requirement",
                             "Corrective Action Plan", 1, None, None, "Case Manager"))

        if len(rows) >= 500:
            db.executemany(
                """INSERT INTO sh.Incident
                   (StayID, IncidentTypeID, IncidentDate, Description,
                    ActionTaken, FollowUpRequired, FollowUpDate, FollowUpNotes, ReportedBy)
                   VALUES (?,?,?,?,?,?,?,?,?)""",
                rows
            )
            db.commit()
            rows = []

    if rows:
        db.executemany(
            """INSERT INTO sh.Incident
               (StayID, IncidentTypeID, IncidentDate, Description,
                ActionTaken, FollowUpRequired, FollowUpDate, FollowUpNotes, ReportedBy)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            rows
        )
        db.commit()
    print("    Incidents complete")


def generate_service_encounters(db: Connection, all_stays, service_type_ids_by_name):
    """
    Generate service encounters.
    Phase 1 (first 90 days): 1 AA/NA meeting per day required.
    Phase 2 (after 90 days): 4+ AA/NA meetings per week required.
    Attendance rates depend on cluster.
    """
    print("  Generating service encounters...")

    CLUSTER_ATTENDANCE = {
        "Reliable":   0.92,
        "Struggling": 0.70,
        "Chronic":    0.45,
    }

    aaname_id    = service_type_ids_by_name.get("AA/NA Meeting")
    house_mtg_id = service_type_ids_by_name.get("House Meeting")
    group_id     = service_type_ids_by_name.get("Group Therapy")
    chore_id     = service_type_ids_by_name.get("Chore Rotation")
    curfew_id    = service_type_ids_by_name.get("Curfew Check-In")

    rows = []

    def flush(rows):
        if rows:
            db.executemany(
                """INSERT INTO sh.ServiceEncounter
                   (StayID, ServiceTypeID, EncounterDate, Attended)
                   VALUES (?,?,?,?)""",
                rows
            )
            db.commit()
        return []

    for stay_id, status, intake, exit_d, bed_id, pid, cluster, cm_id in all_stays:
        attend_rate = CLUSTER_ATTENDANCE[cluster]
        effective_exit = exit_d if exit_d is not None else TODAY
        stay_days   = (effective_exit - intake).days

        cur = intake
        while cur < effective_exit and cur <= END_DATE:
            days_in = (cur - intake).days
            phase = "Phase1" if days_in < 90 else "Phase2"

            # AA/NA meetings
            if aaname_id:
                if phase == "Phase1":
                    # 1 per day
                    attended = random.random() < attend_rate
                    rows.append((stay_id, aaname_id, cur, int(attended)))
                else:
                    # 4+ per week — check on meeting days (Mon/Wed/Fri/Sat)
                    if cur.weekday() in (0, 2, 4, 5):
                        attended = random.random() < attend_rate
                        rows.append((stay_id, aaname_id, cur, int(attended)))

            # House meeting (weekly — every Monday)
            if house_mtg_id and cur.weekday() == 0:
                attended = random.random() < attend_rate
                rows.append((stay_id, house_mtg_id, cur, int(attended)))

            # Group therapy (weekly — every Wednesday)
            if group_id and cur.weekday() == 2:
                attended = random.random() < (attend_rate * 0.85)
                rows.append((stay_id, group_id, cur, int(attended)))

            # Curfew check-in (daily)
            if curfew_id:
                attended = random.random() < (attend_rate * 0.97)
                rows.append((stay_id, curfew_id, cur, int(attended)))

            cur += timedelta(days=1)

            if len(rows) >= 1000:
                rows = flush(rows)

    flush(rows)
    print("    Service encounters complete")


def generate_employment(db: Connection, all_stays):
    """
    Generate employment snapshots.
    Rule: full-time employment required within 15 days.
    Cluster affects employment rate and wage.
    """
    print("  Generating employment snapshots...")

    CLUSTER_EMP_RATE = {
        "Reliable":   {"Full-Time": 0.65, "Part-Time": 0.20, "Unemployed": 0.15},
        "Struggling": {"Full-Time": 0.35, "Part-Time": 0.30, "Unemployed": 0.35},
        "Chronic":    {"Full-Time": 0.10, "Part-Time": 0.20, "Unemployed": 0.70},
    }

    EMPLOYERS = [
        "McDonald's", "Walmart", "Amazon Warehouse", "Dollar General",
        "Home Depot", "Target", "UPS", "Kroger", "Goodwill",
        "Allied Security", "City Maintenance Dept", "Local Auto Shop",
        "Community Center", "Landscaping Co.", "Restaurant Supply Co.",
    ]
    JOBS = {
        "Full-Time": ["Warehouse Associate", "Retail Clerk", "Security Guard",
                      "Maintenance Worker", "Delivery Driver", "Dishwasher",
                      "Custodian", "Line Cook", "General Laborer"],
        "Part-Time": ["Cashier", "Stock Associate", "Food Service Worker",
                      "Cleaning Crew", "Yard Worker"],
    }

    rows = []
    for stay_id, status, intake, exit_d, bed_id, pid, cluster, cm_id in all_stays:
        rates = CLUSTER_EMP_RATE[cluster]
        r = random.random()
        if r < rates["Full-Time"]:
            emp_status = "Full-Time"
            hourly_wage = round(random.uniform(12.00, 22.00), 2)
            hours = random.randint(38, 45)
            job_title = random.choice(JOBS["Full-Time"])
        elif r < rates["Full-Time"] + rates["Part-Time"]:
            emp_status = "Part-Time"
            hourly_wage = round(random.uniform(10.00, 16.00), 2)
            hours = random.randint(15, 32)
            job_title = random.choice(JOBS["Part-Time"])
        else:
            emp_status = "Unemployed"
            hourly_wage = None
            hours = None
            job_title = None

        employer = random.choice(EMPLOYERS) if emp_status != "Unemployed" else None
        start_d = intake + timedelta(days=random.randint(5, 20)) if emp_status != "Unemployed" else None
        effective_exit = exit_d if exit_d is not None else TODAY
        stay_days = (effective_exit - intake).days
        snap_date = intake + timedelta(days=min(30, stay_days))

        rows.append((stay_id, snap_date, emp_status, employer, job_title,
                     hourly_wage, hours, start_d, None))

        # Second snapshot at ~6 months if stay is long enough
        if stay_days > 180:
            snap2 = intake + timedelta(days=180)
            # Struggling/Chronic might improve
            if cluster != "Reliable" and emp_status == "Unemployed" and random.random() < 0.3:
                emp_status = "Part-Time"
                hourly_wage = round(random.uniform(10.00, 15.00), 2)
                hours = random.randint(20, 32)
                job_title = random.choice(JOBS["Part-Time"])
                employer = random.choice(EMPLOYERS)
                start_d = snap2 - timedelta(days=random.randint(7, 30))

            rows.append((stay_id, snap2, emp_status, employer, job_title,
                         hourly_wage, hours, start_d, None))

        if len(rows) >= 500:
            db.executemany(
                """INSERT INTO sh.StayEmploymentSnapshot
                   (StayID, SnapshotDate, EmploymentStatus, Employer, JobTitle,
                    HourlyWage, HoursPerWeek, StartDate, EndDate)
                   VALUES (?,?,?,?,?,?,?,?,?)""",
                rows
            )
            db.commit()
            rows = []

    if rows:
        db.executemany(
            """INSERT INTO sh.StayEmploymentSnapshot
               (StayID, SnapshotDate, EmploymentStatus, Employer, JobTitle,
                HourlyWage, HoursPerWeek, StartDate, EndDate)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            rows
        )
        db.commit()
    print("    Employment snapshots complete")


def generate_rent(db: Connection, all_stays):
    """
    Generate weekly rent charges, payments, and waivers.
    Reliable: 95% payment rate. Struggling: 60%. Chronic: 10%.
    """
    print("  Generating rent charges, payments, waivers...")

    CLUSTER_PAY_RATE = {"Reliable": 0.95, "Struggling": 0.60, "Chronic": 0.10}
    CLUSTER_WAIVER_RATE = {"Reliable": 0.02, "Struggling": 0.15, "Chronic": 0.35}

    charge_rows = []
    payment_rows = []
    waiver_rows = []

    for stay_id, status, intake, exit_d, bed_id, pid, cluster, cm_id in all_stays:
        pay_rate    = CLUSTER_PAY_RATE[cluster]
        waiver_rate = CLUSTER_WAIVER_RATE[cluster]

        # Weekly charges starting on intake Monday
        charge_date = intake
        effective_exit = exit_d if exit_d is not None else TODAY
        while charge_date < effective_exit:
            charge_rows.append((stay_id, charge_date, float(WEEKLY_RENT), "Weekly rent"))
            charge_date += timedelta(days=7)

        if len(charge_rows) >= 2000:
            db.executemany(
                "INSERT INTO sh.RentCharge (StayID, ChargeDate, AmountCharged, Description) VALUES (?,?,?,?)",
                charge_rows
            )
            db.commit()
            charge_rows = []

        # Payments — probabilistic per charge week
        charge_date = intake
        effective_exit = exit_d if exit_d is not None else TODAY
        while charge_date < effective_exit:
            if random.random() < pay_rate:
                pay_date = charge_date + timedelta(days=random.randint(0, 5))
                method = random.choice(["Cash", "Check", "Money Order", "EFT"])
                payment_rows.append((stay_id, pay_date, float(WEEKLY_RENT), method, None))

            charge_date += timedelta(days=7)

        # Waivers (occasional)
        if random.random() < waiver_rate:
            effective_exit = exit_d if exit_d is not None else TODAY
            waiver_date = intake + timedelta(days=random.randint(30, max(31, (effective_exit - intake).days - 7)))
            weeks_waived = random.randint(1, 3)
            amount = float(WEEKLY_RENT) * weeks_waived
            reasons = ["Hardship", "Medical leave", "Job loss", "Emergency",
                       "Administrative adjustment", "Program grant"]
            waiver_rows.append((stay_id, None, waiver_date, amount,
                                 random.choice(reasons), "House Manager"))

    # Flush remaining
    if charge_rows:
        db.executemany(
            "INSERT INTO sh.RentCharge (StayID, ChargeDate, AmountCharged, Description) VALUES (?,?,?,?)",
            charge_rows
        )
    if payment_rows:
        db.executemany(
            """INSERT INTO sh.RentPayment
               (StayID, PaymentDate, AmountPaid, PaymentMethod, Notes)
               VALUES (?,?,?,?,?)""",
            payment_rows
        )
    if waiver_rows:
        db.executemany(
            """INSERT INTO sh.RentWaiver
               (StayID, ChargeID, WaiverDate, AmountWaived, WaiverReason, ApprovedBy)
               VALUES (?,?,?,?,?,?)""",
            waiver_rows
        )
    db.commit()
    print("    Rent records complete")


def generate_outcomes(db: Connection, all_stays):
    """Generate exit outcomes for completed stays."""
    print("  Generating outcomes...")

    DESTINATIONS = [
        ("Independent Housing",   0.30),
        ("Sober Living Home",     0.20),
        ("Family / Friends",      0.18),
        ("Permanent Supportive",  0.10),
        ("Returned to Treatment", 0.08),
        ("Incarceration",         0.06),
        ("Homeless",              0.05),
        ("Unknown",               0.03),
    ]
    DEST_NAMES    = [d[0] for d in DESTINATIONS]
    DEST_WEIGHTS  = [d[1] for d in DESTINATIONS]

    rows = []
    for stay_id, status, intake, exit_d, bed_id, pid, cluster, cm_id in all_stays:
        if status not in ("Completed", "Terminated", "Transferred"):
            continue

        # Primary: exit destination
        destination = weighted_choice(DEST_NAMES, DEST_WEIGHTS)
        rows.append((stay_id, exit_d, "Exit Destination", destination, None))

        # Employment at exit
        if cluster == "Reliable":
            emp_at_exit = "Employed Full-Time" if random.random() < 0.65 else "Employed Part-Time"
        elif cluster == "Struggling":
            emp_at_exit = "Employed" if random.random() < 0.45 else "Unemployed"
        else:
            emp_at_exit = "Employed" if random.random() < 0.15 else "Unemployed"
        rows.append((stay_id, exit_d, "Employment at Exit", emp_at_exit, None))

        # Sobriety length
        effective_exit = exit_d if exit_d is not None else TODAY
        los = (effective_exit - intake).days
        rows.append((stay_id, exit_d, "Sobriety Length (Days)", str(los), None))

        # Program completion flag
        if status == "Completed":
            rows.append((stay_id, exit_d, "Program Completion", "Yes", None))

    if rows:
        db.executemany(
            """INSERT INTO sh.Outcome (StayID, OutcomeDate, OutcomeType, OutcomeValue, Notes)
               VALUES (?,?,?,?,?)""",
            rows
        )
        db.commit()
    print(f"    {len(rows)} outcome records created")


def generate_fundraising(db: Connection):
    """
    Generate donors, fundraising events, and donations.
    2000 donors, 50 events, 25000 donations.
    Seasonal donation patterns (Nov-Dec spike).
    """
    print("  Generating fundraising data...")

    DONOR_TYPES = ["Individual", "Business", "Church", "Foundation", "Anonymous"]
    DONOR_WEIGHTS = [0.72, 0.15, 0.06, 0.04, 0.03]

    # -- Donors --
    donor_ids = []
    for _ in range(NUM_DONORS):
        dtype = weighted_choice(DONOR_TYPES, DONOR_WEIGHTS)
        if dtype == "Individual":
            fname, lname = fake.first_name(), fake.last_name()
            org = None
        elif dtype == "Anonymous":
            fname, lname, org = None, None, "Anonymous"
        else:
            fname, lname = None, None
            org = fake.company()

        did = db.insert_one(
            """INSERT INTO sh.Donor
               (DonorType, OrganizationName, FirstName, LastName,
                Email, Phone, City, StateCode, IsRecurring, FirstDonationDate)
               OUTPUT INSERTED.DonorID
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (dtype, org, fname, lname,
             fake.email() if random.random() < 0.7 else None,
             fake.numerify("(###) ###-####") if random.random() < 0.5 else None,
             fake.city(), fake.state_abbr(),
             int(random.random() < 0.15),
             fake.date_between(START_DATE, TODAY))
        )
        donor_ids.append(did)

    db.commit()
    print(f"    {len(donor_ids)} donors created")

    # -- Fundraising Events --
    event_ids = []
    event_dates = []
    EVENT_TYPES = ["Gala", "Golf Tournament", "Online Campaign", "Walk/Run",
                   "Auction", "Dinner", "Raffle", "Community Day"]

    # Spread events across the full date range
    total_months = (END_DATE.year - START_DATE.year) * 12 + (END_DATE.month - START_DATE.month)
    for i in range(NUM_EVENTS):
        month_offset = int(i * total_months / NUM_EVENTS)
        base_date = date(START_DATE.year + month_offset // 12,
                         (START_DATE.month + month_offset) % 12 or 12, 1)
        edate = base_date + timedelta(days=random.randint(0, 27))
        etype = random.choice(EVENT_TYPES)
        goal = round(random.uniform(5000, 100000), -2)

        eid = db.insert_one(
            """INSERT INTO sh.FundraisingEvent
               (EventName, EventType, EventDate, Goal, Location)
               OUTPUT INSERTED.EventID
               VALUES (?,?,?,?,?)""",
            (f"{etype} {edate.year}", etype, edate, goal,
             fake.city() + ", " + fake.state_abbr())
        )
        event_ids.append(eid)
        event_dates.append(edate)

    db.commit()
    print(f"    {len(event_ids)} events created")

    # -- Donations --
    donation_rows = []
    # Add a "General Fund" event for unattached donations
    general_event_id = None  # None = no event (general donation)

    for _ in range(NUM_DONATIONS):
        donor_id = random.choice(donor_ids)
        don_date = fake.date_between(START_DATE, min(TODAY, END_DATE))

        # Seasonal boost: Nov–Dec donations skew larger (year-end giving)
        if don_date.month in (11, 12):
            amount = round(random.choice([
                random.uniform(25, 200),    # small
                random.uniform(100, 500),   # medium
                random.uniform(250, 1000),  # large (rare)
            ]), 2)
        else:
            amount = round(random.uniform(10, 250), 2)

        # 30% tied to an event — only pick events on or before the donation date
        eligible_events = [eid for eid, edate in zip(event_ids, event_dates)
                           if edate <= don_date]
        if random.random() < 0.30 and eligible_events:
            event_id = random.choice(eligible_events)
        else:
            event_id = None

        dtype = random.choice(["Cash", "Check", "Credit Card", "In-Kind", "Online"])
        is_anon = int(random.random() < 0.08)

        donation_rows.append((donor_id, event_id, don_date, amount,
                               dtype, is_anon, None, None))

        if len(donation_rows) >= 1000:
            db.executemany(
                """INSERT INTO sh.FundraisingDonation
                   (DonorID, EventID, DonationDate, Amount,
                    DonationType, IsAnonymous, Campaign, Notes)
                   VALUES (?,?,?,?,?,?,?,?)""",
                donation_rows
            )
            db.commit()
            donation_rows = []

    if donation_rows:
        db.executemany(
            """INSERT INTO sh.FundraisingDonation
               (DonorID, EventID, DonationDate, Amount,
                DonationType, IsAnonymous, Campaign, Notes)
               VALUES (?,?,?,?,?,?,?,?)""",
            donation_rows
        )
        db.commit()
    print(f"    {NUM_DONATIONS} donations created")


def generate_financial_assistance(db: Connection, all_stays):
    """
    Generate third-party program payments for a subset of stays.
    ~25% of stays receive 1-3 payments from a randomly selected program.
    Amounts reflect realistic assistance: $200-$800 per payment.
    Donation dates are always within the stay window.
    """
    print("  Generating financial assistance...")

    # Fetch all program IDs
    db.execute("SELECT ProgramID FROM sh.FinancialAssistanceProgram")
    program_ids = [row[0] for row in db.fetchall()]
    if not program_ids:
        print("    No programs found — skipping.")
        return

    rows = []
    for stay in all_stays:
        stay_id    = stay[0]   # stay_id
        intake     = stay[2]   # intake_date
        exit_d     = stay[3]   # actual_exit

        # Skip stays that haven't started yet
        if intake > TODAY:
            continue
        # Payments can extend through the full stay window (including future for active stays)
        pay_end = exit_d

        # Only ~25% of stays receive assistance
        if random.random() > 0.25:
            continue

        num_payments = random.randint(1, 3)
        program_id   = random.choice(program_ids)

        for _ in range(num_payments):
            # Payment date falls within the stay window
            pay_date = fake.date_between(intake, pay_end)
            amount   = round(random.uniform(200, 800), 2)
            notes    = None
            rows.append((stay_id, program_id, pay_date, amount, notes))

    db.executemany(
        """INSERT INTO sh.ProgramPayment (StayID, ProgramID, PaymentDate, AmountPaid, Notes)
           VALUES (?,?,?,?,?)""",
        rows
    )
    db.commit()
    print(f"    {len(rows)} program payments created")


# ===========================================================================
# LOOKUP ID FETCHERS
# ===========================================================================

def fetch_lookup_ids(db: Connection, table: str, id_col: str, name_col: str) -> dict:
    db.execute(f"SELECT {name_col}, {id_col} FROM sh.{table}")
    return {row[0]: row[1] for row in db.fetchall()}


def fetch_id_list(db: Connection, table: str, id_col: str) -> list:
    db.execute(f"SELECT {id_col} FROM sh.{table}")
    return [row[0] for row in db.fetchall()]


# ===========================================================================
# MAIN
# ===========================================================================

def main():
    print("=" * 60)
    print("Serenity House Synthetic Data Generator v6")
    print(f"  Residents: {NUM_RESIDENTS}")
    print(f"  Date range:   {START_DATE} → {END_DATE}")
    print(f"  Donors:       {NUM_DONORS} | Events: {NUM_EVENTS} | Donations: {NUM_DONATIONS}")
    print("=" * 60)

    db = Connection()
    try:
        print("\n[1/9] Housing setup")
        house_id, room_ids, bed_ids = generate_house_room_beds(db)

        print("\n[2/9] Case managers")
        case_manager_ids = generate_case_managers(db)

        print("\n[3/9] Residents")
        resident_ids, clusters = generate_residents(db)

        print("\n[4/9] Stays (seasonal occupancy)")
        referral_source_ids = fetch_id_list(db, "ReferralSource", "ReferralSourceID")
        all_stays = generate_stays(db, resident_ids, clusters,
                                   bed_ids, case_manager_ids, referral_source_ids)

        print("\n[5/9] Drug tests")
        generate_drug_tests(db, all_stays)

        print("\n[6/9] Incidents")
        incident_type_ids_by_name = fetch_lookup_ids(db, "IncidentType", "IncidentTypeID", "TypeName")
        generate_incidents(db, all_stays, incident_type_ids_by_name)

        print("\n[7/9] Service encounters")
        service_type_ids_by_name = fetch_lookup_ids(db, "ServiceType", "ServiceTypeID", "ServiceName")
        generate_service_encounters(db, all_stays, service_type_ids_by_name)

        print("\n[8/9] Employment, rent, outcomes")
        generate_employment(db, all_stays)
        generate_rent(db, all_stays)
        generate_outcomes(db, all_stays)

        print("\n[9/10] Financial assistance programs")
        generate_financial_assistance(db, all_stays)

        print("\n[10/10] Fundraising")
        generate_fundraising(db)

        print("\n" + "=" * 60)
        print("Generation complete.")
        print("=" * 60)

    except Exception as e:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
