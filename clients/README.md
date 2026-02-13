# Employer Clients Directory

Standard file structure for all employer audit engagements.

## Directory Structure

```
clients/
├── README.md                          # This file
├── {employer-slug}/                   # One directory per employer
│   ├── manifest.json                  # Client metadata, project status, deliverable index
│   ├── deliverables/                  # All generated documents
│   │   ├── {EMPLOYER}_AUDIT_ANALYSIS.md    # Internal analysis (from utilization report)
│   │   ├── {EMPLOYER}_CLIENT_REPORT.md     # Client-facing report
│   │   ├── EXECUTIVE_SUMMARY_1PAGE.md      # One-page summary for decision-maker
│   │   ├── CONSENT_AUTHORIZATION.md        # ERISA data access authorization
│   │   ├── SLACK_POST.md                   # Internal stakeholder update
│   │   └── SUMMARY.md                      # Internal executive summary
│   ├── prds/                          # Project requirement documents
│   │   └── {slug}-p{N}-{name}.md      # Individual project PRDs
│   └── data/                          # Source data and extracts
│       ├── utilization-report.pdf     # Original broker report (if available)
│       └── claims/                    # Raw claims data (after consent)
```

## Creating a New Employer

1. Create the directory: `mkdir -p clients/{employer-slug}/{deliverables,prds,data}`
2. Copy `manifest.json` from an existing client and update fields
3. Run analysis on their utilization report
4. Generate deliverables using the template: `templates/employer-pilot-report.md`

## Manifest Schema

The `manifest.json` file is the single source of truth for:
- Client metadata (name, size, TPA, funding type)
- Engagement status and phase
- Project tracking with dependencies
- Deliverable inventory with types (client/internal/legal)

The dashboard reads this file to render the client document portal.
