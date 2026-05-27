# RDL / SSRS Paginated Report — Lessons Learned

This document captures hard-won fixes and patterns discovered while building
`ResidentReport.rdl` for the Serenity House PoC. Consult it before starting
any new `.rdl` project.

---

## 1. Use a Python generator script, not hand-edited XML

Writing RDL by hand is error-prone and slow. Instead, maintain a Python script
(`gen_rdl.py`) that builds the XML programmatically using helper functions.
Benefits:
- A single change to a helper (e.g. a border fix) propagates everywhere
- Regenerate the file cleanly after any corruption
- Helper functions encode the correct patterns so you can't accidentally
  introduce a schema error twice
- The script is the source of truth; the `.rdl` file is an output

Run it with: `python gen_rdl.py`

Validate XML immediately after generation:
```python
import xml.etree.ElementTree as ET
ET.parse("reports/ResidentReport.rdl")
```

---

## 2. RDL 2016 schema — valid border elements

The 2016 schema (`http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition`)
**rejects** the shorthand border properties as direct children of `<Style>`.

❌ Invalid — Report Builder will throw a schema error on load:
```xml
<Style>
  <BorderColor>#1F4E79</BorderColor>
  <BorderStyle>Solid</BorderStyle>
  <BorderWidth>2pt</BorderWidth>
</Style>
```

✅ Valid — use the directional border elements:
```xml
<Style>
  <Border><Style>None</Style></Border>
  <BottomBorder><Color>#1F4E79</Color><Style>Solid</Style><Width>2pt</Width></BottomBorder>
  <TopBorder><Color>#CCCCCC</Color><Style>Solid</Style><Width>1pt</Width></TopBorder>
</Style>
```

Available directional elements: `<Border>`, `<TopBorder>`, `<BottomBorder>`,
`<LeftBorder>`, `<RightBorder>`.

---

## 3. XML-escape `&` in VB expressions

SSRS expression strings are embedded as XML element content. The XML parser
runs **before** SSRS evaluates the expression, so `&` must always be `&amp;`
— even inside a VB concatenation operator.

❌ Causes an XML parse error:
```xml
<Value>=Fields!FullName.Value & " years"</Value>
```

✅ Correct:
```xml
<Value>=Fields!FullName.Value &amp; " years"</Value>
```

In the generator script, run all values through an escape function before
embedding them:
```python
def xv(v):
    return v.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
```

---

## 4. Layout architecture — use a flowing outer Tablix, not absolute positioning

### The problem with absolute positioning inside a Rectangle

The intuitive approach is to put all report items inside a `<Rectangle>`
container and position them with absolute `<Top>` values. This works in
Report Builder's interactive Preview tab (which uses a soft HTML renderer)
but breaks in PDF/print output (hard physical renderer) because:

- Items with `CanGrow=true` expand downward but **do not push siblings down**
- The next item is still at its fixed absolute position, causing overlap or
  unexpected gaps
- The total Rectangle height equals the bottom of the last item — if it
  exceeds the printable area, SSRS adds extra blank pages

### The correct architecture — flowing outer Tablix

Use a single-column Tablix as the body container with no dataset binding.
Each section is one or more **rows** in that Tablix:

```
Outer Tablix (1 column, 6.5in wide, no dataset)
├── TablixRow: RESIDENT OVERVIEW header (section header textbox)
├── TablixRow: Overview data (nested static Tablix)
├── TablixRow: spacer (0.15in)
├── TablixRow: FINANCIAL SUMMARY header
├── TablixRow: KPI data (nested static Tablix)
├── TablixRow: spacer
├── TablixRow: PAYMENT HISTORY header
├── TablixRow: Payment detail (nested detail Tablix, CanGrow)
├── TablixRow: spacer
├── TablixRow: INCIDENT HISTORY header
├── TablixRow: Incident detail (nested detail Tablix, CanGrow)
├── TablixRow: spacer
├── TablixRow: DRUG TEST HISTORY header
└── TablixRow: Drug test detail (nested detail Tablix, CanGrow)
```

When a nested detail Tablix grows (more data rows), the outer Tablix row
grows with it, and all subsequent rows shift down automatically.
**This is the architecture that renders consistently between Preview and PDF.**

---

## 5. Eliminate trailing blank pages — ConsumeContainerWhitespace

Add this to the `<Report>` element (before `<DataSources>`):

```xml
<ConsumeContainerWhitespace>true</ConsumeContainerWhitespace>
```

This tells SSRS not to allocate extra pages for whitespace below the last
rendered item. Without it, a report whose content ends partway down page 2
will often generate a blank page 3.

Also keep the `<Body><Height>` small (e.g. `0.1in`) — SSRS uses the larger
of declared height and actual rendered height, so a large declared height
will always pad extra pages.

---

## 6. Detail Tablix — header row member pattern

For a detail (repeating) Tablix, the `<TablixRowHierarchy>` must declare the
header row member with `KeepWithGroup=After` and `RepeatOnNewPage=true`, and
the detail row member must have a `<Group>` element:

```xml
<TablixRowHierarchy>
  <TablixMembers>
    <TablixMember>
      <KeepWithGroup>After</KeepWithGroup>
      <RepeatOnNewPage>true</RepeatOnNewPage>
      <KeepTogether>true</KeepTogether>
    </TablixMember>
    <TablixMember>
      <Group Name="PaymentDetail"/>
      <TablixMembers><TablixMember/></TablixMembers>
    </TablixMember>
  </TablixMembers>
</TablixRowHierarchy>
```

`RepeatOnNewPage=true` makes column headers re-appear at the top of each
continuation page when a section spans a page break.

---

## 7. Empty / optional cells — use VB empty string expression

To show a blank cell (rather than a literal `""` or `null`), use a VB
expression that evaluates to an empty string:

❌ Shows literal double-quotes in the report:
```xml
<Value>""</Value>
```

✅ Evaluates to empty string:
```xml
<Value>=""</Value>
```

For nullable fields, use `IIF(IsNothing(...), "", ...)`:
```xml
<Value>=IIF(IsNothing(Fields!Note.Value), "", Fields!Note.Value)</Value>
```

---

## 8. Column widths must sum exactly to content width

The sum of all `<TablixColumn><Width>` values must equal the declared table
width (and the body/section width). Off-by-a-fraction errors cause rendering
artifacts in PDF output.

Page setup used in ResidentReport:
- Page: 8.5 × 11 in
- Left/right margins: 1 in each
- Content width: **6.5 in**
- Top margin: 1 in, Bottom margin: 0.75 in
- Page header height: 0.6 in, Page footer height: 0.4 in
- Printable content height per page: **8.25 in**

Column widths per section (all sum to 6.5 in):

| Section | Widths |
|---------|--------|
| Resident Overview | 1.5, 1.75, 1.5, 1.75 |
| Financial KPI | 1.3, 1.3, 1.3, 1.3, 1.3 |
| Payment History | 0.9, 0.75, 1.0, 1.7, 2.15 |
| Incident History | 0.9, 1.5, 0.8, 1.7, 1.6 |
| Drug Test History | 0.9, 1.0, 0.9, 0.75, 2.95 |

---

## 9. Credentials and gitignore

Connection strings containing server names, usernames, or passwords must
never be committed to git.

`.gitignore` entries added:
```
# Connection strings / secrets
python/config.py
*.env

# Paginated reports — may contain server names or cached credentials
reports/
```

The `reports/` folder exclusion covers `.rdl` files (which embed the
connection string) and any exported PDFs. Distribute the RDL file separately
from the repo.

For development, SQL authentication credentials are embedded directly in the
generator script's connection string and are regenerated into the `.rdl` on
each run. Before any production deployment, rotate credentials and review
the security model.

---

## 10. Regenerating after corruption

If the generator script is accidentally zeroed or corrupted:

1. Restore from git: `git checkout gen_rdl.py`
2. If not committed, rebuild from this document and the RDL itself as
   reference — the RDL is the rendered output of the script logic
3. Never edit the `.rdl` file directly for structural changes; always fix
   the generator and regenerate
4. Minor text/value fixes can be made directly in the `.rdl` if the
   generator will be regenerated anyway

---

## 11. Report Builder workflow tips

- **Close the `.rdl` file in Report Builder before regenerating** — the file
  is locked while open and writes will silently fail or corrupt it
- **Print Layout view** (View menu → Print Layout) shows the true physical
  page rendering; the default Preview tab uses a soft renderer that hides
  spacing and page break issues
- **After reloading**, always click View Report — the parameter dropdown
  does not auto-run
- **Save to PDF via** File → Export → PDF for a faithful reproduction of
  what will print; don't use the browser print function on the preview

---

---

## 12. PDF renderer vs interactive renderer — the critical difference

**Interactive preview** (Report Builder Preview tab, Word export) uses a soft
renderer that dynamically sizes items based on their content. Items grow and
the layout reflows. Sections that contain nested data regions expand their
parent containers. This is why reports look correct in preview.

**PDF / Print** uses a hard physical renderer. Items render at their exact
declared absolute coordinates. Nothing reflows. If an item grows beyond its
declared size (due to CanGrow), it overflows into the space below — but the
next absolutely-positioned item does not move. This causes section overlap.

The Word export (.docx) uses the soft renderer and looks correct. Printing
that Word file to PDF via Microsoft Print to PDF also produces overlap because
Print to PDF re-renders using physical layout, not the Word soft renderer.

**Rule:** Design and test paginated reports in Print Layout view
(View → Print Layout in Report Builder), which shows the physical renderer.
The Preview tab is misleading for print/PDF use cases.

---

## 13. The TOP N fixed-height pattern — standard practice for print/PDF reports

The only reliable way to guarantee no section overlap in a PDF-rendered SSRS
report with variable-length detail sections is to cap rows to a known maximum
and size the section heights to match exactly.

### Why it works

With `TOP N` in the SQL query, the maximum number of rows is bounded at design
time. You can calculate the exact section height:

```
section_height = section_header + column_header + (N × row_height)
```

Because the height is known and fixed, the next section can be absolutely
positioned at exactly `previous_section_top + previous_section_height + gap`.
No overlap is possible regardless of how many rows the data actually returns
(it will be ≤ N).

### Row heights used in ResidentReport

| Section | Row height | Reason |
|---------|-----------|--------|
| Overview | 0.28in | Single-line label/value pairs |
| Financial KPI | 0.30in | Slightly taller header+data rows |
| Payment History | 0.28in | Short date/amount/method values |
| Incident History | 0.45in | Description column wraps to ~2 lines |
| Drug Test History | 0.28in | Short values |

### Section positions (ResidentReport, TOP 10)

```
Section             top      height   ends
RESIDENT OVERVIEW   0.00in   2.00in   2.00in
[gap]               2.00in   0.30in   2.30in
FINANCIAL SUMMARY   2.30in   0.92in   3.22in
[gap]               3.22in   0.30in   3.52in
PAYMENT HISTORY     3.52in   3.42in   6.94in  (hdr 0.32 + col 0.30 + 10×0.28)
[gap]               6.94in   0.30in   7.24in
INCIDENT HISTORY    7.24in   4.62in  11.86in  (hdr 0.32 + col 0.30 + 10×0.45)
[gap]              11.86in   0.30in  12.16in
DRUG TEST HISTORY  12.16in   3.42in  15.58in  (hdr 0.32 + col 0.30 + 10×0.28)

Body height: 15.58in  →  15.58 ÷ 8.25in per page = 1.89 pages → exactly 2 pages
```

### Tradeoffs

- Residents with fewer than 10 rows get blank rows at the bottom of each
  section — acceptable whitespace for guaranteed no-overlap
- Residents with more than 10 rows see only the 10 most recent — add a note
  in the section header label like "PAYMENT HISTORY (10 most recent)"
- If you need to show more rows, increase N and recalculate section heights
  and positions throughout the layout table above

---

## 14. Python f-string limitation with backslashes in expressions

Python versions before 3.12 do not allow backslash characters inside f-string
`{}` expression blocks. When building the RDL in an f-string, any argument
to a helper function that contains escaped quotes (`\"`) will cause a
`SyntaxError`.

**Fix:** Pre-compute any page header/footer strings that contain quotes
*before* the f-string, then reference the pre-computed variables inside `{}`:

```python
# Outside the f-string — quotes work fine here
_hdr_name = page_tb("hdrResName",
                    '=First(Fields!FullName.Value,"dsResidentOverview")',
                    "0.05in","3.5in","0.22in","3in",align="Right")

# Inside the f-string — just reference the variable
rdl += f\'\'\'
  ...{_hdr_name}...
\'\'\'
```

---

*Last updated: May 2026 — Serenity House PoC, ResidentReport.rdl v2 (TOP 10 fixed-height layout)*
