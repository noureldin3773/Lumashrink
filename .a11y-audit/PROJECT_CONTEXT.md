# Accessibility Audit Project Context

## Project

- name: LumaShrink
- base_url: http://127.0.0.1:8765
- repo_root: .
- app_root: .

## Audit Scope

- standards: WCAG 2.1 AA
- scan_mode: full
- include_routes:
  - /
  - /app
  - /privacy
  - /terms
  - /support
- priority_routes:
  - /
  - /app

## Output Configuration

- output_mode: markdown
- report_path: docs/accessibility/audits/audit-YYYY-MM-DD.md
