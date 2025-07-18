$Repo = "markus-lassfolk/rutos-starlink-failover"
$PrNumber = 72

Write-Host "🚀 Manually triggering the Autonomous Copilot workflow for PR #$PrNumber..." -ForegroundColor Cyan

# Trigger the workflow manually by dispatching a "workflow_dispatch" event (pull_request event can't be triggered directly)
gh workflow run "Autonomous Copilot Manager" --repo $Repo

Write-Host "⏳ Waiting 30 seconds for workflow to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Fetch the latest run for this workflow
$Run = gh run list --repo $Repo --workflow "Autonomous Copilot Manager" --limit 1 --json databaseId,status,conclusion,displayTitle |
    ConvertFrom-Json | Select-Object -First 1

$RunId = $Run.databaseId
Write-Host "📄 Latest Run: $($Run.displayTitle) | Status: $($Run.status) | Conclusion: $($Run.conclusion)" -ForegroundColor Cyan

Write-Host "🔍 Fetching logs for Run ID $RunId..." -ForegroundColor Yellow
gh run view $RunId --repo $Repo --log > ".\copilot-autonomous-log.txt"

Write-Host "`n✅ Log saved to: .\copilot-autonomous-log.txt" -ForegroundColor Green
Write-Host "Showing the last 50 lines:" -ForegroundColor Cyan
Get-Content ".\copilot-autonomous-log.txt" -Tail 50
