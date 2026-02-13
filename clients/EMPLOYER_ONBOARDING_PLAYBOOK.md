# Employer Onboarding Playbook

**How to create a complete audit package for a new employer client.**

Replicates the process used for Noveon Magnetics (first client, February 2026). Follow these steps in order — each step builds on the previous.

---

## Prerequisites

- Employer's utilization report (PDF from their TPA/broker — Cigna, UHC, BCBS, Aetna, etc.)
- Contact info: who referred them, who the decision-maker is, their role
- Basic company profile: name, industry, approximate employee count

---

## Step 1: Create the Client Directory

```bash
SLUG="employer-name"  # lowercase, hyphenated (e.g., "noveon-magnetics")
mkdir -p ~/.claude-orchestrator/clients/${SLUG}/{deliverables,prds,data}
```

Place the source utilization report PDF (if available) in `data/`:
```bash
cp /path/to/utilization-report.pdf ~/.claude-orchestrator/clients/${SLUG}/data/
```

---

## Step 2: Analyze the Utilization Report

Read the full utilization report and create the internal analysis document. Extract:

### Company Profile
- Company name, group number, employee count, member count
- Average age, % female, turnover rate
- Broker name, account executive
- **Plan type and funding arrangement** (critical — determines self-insured status)
- Network type

### Financial Overview
- Total plan spend (base period vs current period)
- PMPM breakdown: total, medical, pharmacy, employer-paid, member cost share
- How each metric compares to TPA norms
- Monthly funding flow (if level-funded)
- Annualized run rate

### High-Value Audit Opportunities
For each opportunity, capture:
- **What it is**: condition, member demographics (de-identified), total cost
- **Why it's auditable**: billing complexity, pricing variance, alternative sourcing
- **Savings estimate**: conservative and moderate ranges with methodology
- **Specific actions**: what interventions would capture the savings

### Common Patterns to Look For
1. **Catastrophic cases** (>$100K) — cancer, transplant, NICU, specialty surgery
2. **GLP-1 drug trajectory** — Mounjaro, Ozempic, Wegovy adoption and cost
3. **Specialty pharmacy concentration** — one member driving most specialty Rx spend
4. **Lab steerage gaps** — high % going to non-preferred (expensive) labs
5. **ER steerage** — visits for conditions treatable at urgent care
6. **Low preventive care engagement** — well visits, screenings below norms
7. **Suspicious adjustments** — large negative adjustments on claims
8. **Self-insured status** — level-funded or ASO arrangements = ERISA data rights

### Output File
Save as: `clients/${SLUG}/deliverables/${EMPLOYER}_AUDIT_ANALYSIS.md`

Use `clients/noveon-magnetics/deliverables/NOVEON_AUDIT_ANALYSIS.md` as the reference template. Match the structure:
- Company Profile table
- Critical Insight (self-insured status if applicable)
- Financial Overview with comparison tables
- Numbered audit opportunities with detail tables and savings estimates
- Total Savings Estimate summary table
- Product Fit Analysis (Product A: Bill Audit, Product B: Claims Platform)
- Pitch Angle section with opening line and key stories
- Additional Data Points for reference

---

## Step 3: Create Client-Facing Deliverables

Use the internal analysis to generate these documents. Reference the Noveon versions and the reusable template.

### 3a. Client Report (the "wow" document)

**Template**: `~/.claude-orchestrator/templates/employer-pilot-report.md`
**Reference**: `clients/noveon-magnetics/deliverables/NOVEON_CLIENT_REPORT.md`
**Output**: `clients/${SLUG}/deliverables/${EMPLOYER}_CLIENT_REPORT.md`

Key sections:
1. **"Broker vs. Us" comparison** — what the standard report shows vs what we found
2. **Top 5 savings opportunities** — ranked by dollar impact, CFO-readable language
3. **Total savings summary table** — conservative and moderate columns
4. **Self-insured education** (if applicable) — ERISA rights, what raw claims enable
5. **Engagement gap** — preventive care metrics vs norms
6. **Recommended next steps** — immediate, short-term, medium-term, ongoing

**Quality checklist**:
- [ ] All dollar figures cross-referenced against internal analysis
- [ ] No PHI (no names, no specific ages, no ICD-10 codes, no dates of service)
- [ ] Savings estimates match source exactly (not rounded differently)
- [ ] PMPM defined on first use ("Per Member Per Month")
- [ ] BAA mentioned alongside consent authorization
- [ ] No unsourced marketing claims (e.g., "typically finds 2-3x more")
- [ ] Readable by a non-insurance CFO in 15 minutes

### 3b. One-Page Executive Summary

**Reference**: `clients/noveon-magnetics/deliverables/EXECUTIVE_SUMMARY_1PAGE.md`
**Output**: `clients/${SLUG}/deliverables/EXECUTIVE_SUMMARY_1PAGE.md`

Contains only:
- Key finding (one sentence with total savings range)
- Top 3 opportunities table (number, description, savings range)
- Self-insured insight (if applicable, 2-3 sentences)
- Engagement gap (one stat)
- Call to action (sign consent authorization)

### 3c. Consent Authorization (if self-insured)

**Reference**: `clients/noveon-magnetics/deliverables/CONSENT_AUTHORIZATION.md`
**Output**: `clients/${SLUG}/deliverables/CONSENT_AUTHORIZATION.md`

Customize:
- Employer name and group number
- TPA name
- Plan type description
- Data period requested
- Contact/delivery information

**Always include** the legal notice: "This is a template authorization. [Employer] should have this document reviewed by legal counsel before execution."

### 3d. Internal Slack Post

**Reference**: `clients/noveon-magnetics/deliverables/SLACK_POST.md`
**Output**: `clients/${SLUG}/deliverables/SLACK_POST.md`

Structure:
- tl;dr (one line: who, what, how much)
- Headlines (2-3 key stories)
- Numbers table (opportunities and savings ranges)
- Deliverables ready (list of files)
- Next steps (who does what)
- Strategic value (how this feeds the flywheel)

### 3e. Internal Summary

**Reference**: `clients/noveon-magnetics/deliverables/SUMMARY.md`
**Output**: `clients/${SLUG}/deliverables/SUMMARY.md`

Compact version of the internal analysis: company, key finding, top opportunities, critical insight, product fit, risk factors, deliverable index.

---

## Step 4: Create Project PRDs

For each employer, determine which projects from the 7-project strategy are applicable. Not every employer needs all 7 — the first three are always relevant.

### Always Create
- **P1: Pilot Audit Report** (CRITICAL) — the client deliverable itself
- **P2: Utilization Report Parser** (HIGH) — if their TPA format isn't already supported
- **P3: Raw Claims Ingestion** (HIGH) — if they're self-insured

### Create If Applicable
- **P6: GLP-1 Playbook** (HIGH) — if they have GLP-1 spend
- **P4-P5-P7** (STRATEGIC) — these are cross-employer, not per-employer

**PRD naming convention**: `{slug}-p{N}-{name}.md`
**Output directory**: `clients/${SLUG}/prds/`
**Reference PRDs**: `clients/noveon-magnetics/prds/`

---

## Step 5: Create the Manifest

**Template**: `clients/noveon-magnetics/manifest.json`
**Output**: `clients/${SLUG}/manifest.json`

Update all fields:
```json
{
  "client": {
    "name": "...",
    "slug": "...",
    "industry": "...",
    "employees": 0,
    "members": 0,
    "tpa": "...",
    "fundingType": "level-funded | fully-insured | self-insured",
    "selfInsured": true | false,
    "groupNumber": "...",
    "broker": "...",
    "contact": { "name": "...", "title": "...", "referredBy": "..." }
  },
  "engagement": {
    "status": "pilot",
    "startDate": "YYYY-MM-DD",
    "phase": "Phase 1 — Prove Value",
    "consentStatus": "pending",
    "annualizedSpend": 0,
    "savingsEstimate": { "conservative": 0, "moderate": 0 }
  },
  "projects": [...],
  "deliverables": [...]
}
```

---

## Step 6: Add to Backlog

```bash
BACKLOG=~/.claude-orchestrator/scripts/backlog.sh

$BACKLOG add "${EMPLOYER} P1: Create client-facing pilot audit report" \
  --priority critical --source project \
  --description "PRD: clients/${SLUG}/prds/${SLUG}-p1-pilot-audit-report.md"

# Repeat for each project PRD created
```

---

## Step 7: Register in Dashboard

Add the new client slug to `KNOWN_CLIENTS` in `dashboard/clients.html`:

```javascript
const KNOWN_CLIENTS = ['noveon-magnetics', 'new-employer-slug'];
```

The dashboard will automatically read their `manifest.json` and display all deliverables and projects.

---

## Step 8: Verify

Run through the P1 verification checklist:
- [ ] All dollar figures match source analysis
- [ ] No PHI in client-facing documents
- [ ] Savings estimates are conservative and defensible
- [ ] Self-insured explanation is accurate (if applicable)
- [ ] Consent template has legal notice
- [ ] Report is CFO-readable (no unexplained jargon)
- [ ] Manifest.json is complete and valid JSON
- [ ] Dashboard renders the new client correctly

---

## File Inventory (per employer)

| File | Type | Audience |
|------|------|----------|
| `deliverables/{EMPLOYER}_AUDIT_ANALYSIS.md` | Internal | Team |
| `deliverables/{EMPLOYER}_CLIENT_REPORT.md` | Client | Decision-maker |
| `deliverables/EXECUTIVE_SUMMARY_1PAGE.md` | Client | Decision-maker (quick read) |
| `deliverables/CONSENT_AUTHORIZATION.md` | Legal | Decision-maker (sign) |
| `deliverables/SLACK_POST.md` | Internal | Team Slack |
| `deliverables/SUMMARY.md` | Internal | Team reference |
| `prds/{slug}-p1-*.md` | Internal | Engineering/planning |
| `manifest.json` | System | Dashboard |

---

## Reference: Noveon Magnetics (First Client)

- **Slug**: `noveon-magnetics`
- **Source**: 44-page Cigna Utilization Review, January 2026
- **Key findings**: $224K cancer case, GLP-1 explosion ($0→$68K), $61K Rinvoq
- **Total savings**: $44,750–$97,360 annually
- **Critical insight**: Self-insured (level-funded 50%), ERISA data rights
- **Projects created**: 7 (P1 complete, P2-P7 pending)
- **Onboarded**: 2026-02-13

---

*Last updated: 2026-02-13*
