gh api repos/$Repo/actions/permissions/workflow -f default_workflow_permissions=write -f can_approve_pull_request_reviews=true -f retention_days=7
