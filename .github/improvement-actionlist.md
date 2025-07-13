# Live Improvement Action List (Branch: improvements/actionlist-2025-07)

This document tracks ongoing improvements for the July 2025 enhancement cycle. Each item will be checked off as it is completed in this branch/PR.

## Action Items

- [ ] **File Permissions & Secret Scanning**
    - Add script/CI check for file permissions, hardcoded secrets, and secure config values
    - Integrate `gitleaks` for secret scanning
- [ ] **Upgrade Script**
    - Add `upgrade.sh` to safely update scripts/configs without overwriting user changes
- [ ] **Version Check & Self-Update**
    - Provide version check and self-update mechanism
- [ ] **Granular Notification Controls**
    - Add options to notify only on critical errors, soft/hard failover, or both
    - Add more notification channel options if feasible
- [ ] **Automated API Schema Diffing & Alerting**
    - Add tool/script to diff Starlink API schema and alert on changes
- [ ] **API Change Response Process**
    - Document process for quickly updating scripts when Starlink API changes
- [ ] **ShellCheck & Formatting Enforcement**
    - Enforce ShellCheck and formatting checks for all shell scripts in CI
- [ ] **Code Comments & Maintainability**
    - Add comments to all functions and complex logic for maintainability

---

*This list is live and will be updated as improvements are made. See PR for progress and discussion.*
