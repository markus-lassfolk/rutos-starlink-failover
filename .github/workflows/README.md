# GitHub Workflows for Go Project

This directory contains optimized GitHub Actions workflows for the Go-based RUTOS Starlink Failover project.

## 🎯 Workflow Overview

### Core Go Workflows

| Workflow | Purpose | Triggers | Status |
|----------|---------|----------|---------|
| `go-build-test.yml` | Build, test, and validate Go code | Go files, go.mod, go.sum | ✅ Active |
| `go-lint-format.yml` | Lint, format, and auto-fix Go code | Go files, go.mod, go.sum | ✅ Active |
| `integration-tests.yml` | Run comprehensive integration tests | Go files, scripts, tests | ✅ Active |

### Quality Assurance Workflows

| Workflow | Purpose | Triggers | Status |
|----------|---------|----------|---------|
| `docs-check.yml` | Validate documentation and comments | Go files, markdown files | ✅ Active |
| `check-security.yml` | Security scanning and vulnerability checks | Go files, dependencies | ✅ Active |
| `dependency-check.yml` | Dependency management and license checks | go.mod, go.sum | ✅ Active |

### Disabled Workflows

The following autonomous workflows have been disabled to prevent interference with Go development:

- `ultimate-autonomous-orchestrator.yml.disabled`
- `autonomous-copilot.yml.disabled`
- `autonomous-pr-merger.yml.disabled`
- `auto-resolve-mixed-status.yml.disabled`

## 🚀 Workflow Features

### Go Build & Test (`go-build-test.yml`)

**Features:**
- Multi-version Go testing (1.21, 1.22)
- Comprehensive test coverage with race detection
- Security scanning with gosec
- Multi-platform builds (Linux, Windows, ARM64)
- Performance benchmarking
- Static analysis with golangci-lint
- Artifact archiving

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Only when Go files, go.mod, or go.sum are changed

### Go Lint & Format (`go-lint-format.yml`)

**Features:**
- Auto-formatting with goimports, gofumpt, and go fmt
- Comprehensive linting with golangci-lint
- Security scanning with gosec and staticcheck
- Deprecated function detection
- Common Go issue detection
- Auto-commit formatting changes on push

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Only when Go files, go.mod, or go.sum are changed

### Integration Tests (`integration-tests.yml`)

**Features:**
- Matrix testing (unit, integration, e2e)
- Performance and stress testing
- Binary functionality testing
- Compatibility testing
- Comprehensive test reporting
- Coverage analysis

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Weekly scheduled runs (Sunday 2 AM)

### Documentation Check (`docs-check.yml`)

**Features:**
- Go documentation validation
- API documentation checks
- README validation
- Markdown link checking
- Code comment quality analysis
- TODO/FIXME detection

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Only when Go files or markdown files are changed

### Security Check (`check-security.yml`)

**Features:**
- Multiple security scanners (gosec, Trivy, Grype)
- Dependency vulnerability scanning
- License compliance checking
- Hardcoded secret detection
- Unsafe code pattern detection
- SQL/command injection detection

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Weekly scheduled runs (Sunday 3 AM)

### Dependency Check (`dependency-check.yml`)

**Features:**
- Dependency verification and tidying
- License compliance checking
- Vulnerability scanning
- Dependency graph analysis
- Deprecated dependency detection

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Weekly scheduled runs (Sunday 4 AM)

## 📋 Workflow Configuration

### Branch Protection

These workflows are designed to work with branch protection rules:

- **Required Status Checks:**
  - `Go Build & Test`
  - `Go Lint & Format`
  - `Integration Tests`
  - `Documentation Check`
  - `Security Check`
  - `Dependency Check`

### Path-Based Triggers

All workflows use path-based triggers to avoid unnecessary runs:

- **Go files:** `**/*.go`, `cmd/**`, `pkg/**`
- **Dependencies:** `go.mod`, `go.sum`
- **Documentation:** `**/*.md`, `docs/**`, `README.md`
- **Scripts:** `scripts/**`, `tests/**`

### Matrix Strategies

Some workflows use matrix strategies for comprehensive testing:

- **Go versions:** 1.21, 1.22
- **Test suites:** unit, integration, e2e
- **Platforms:** Linux, Windows, ARM64

## 🔧 Customization

### Adding New Workflows

1. Create a new `.yml` file in this directory
2. Follow the naming convention: `purpose-action.yml`
3. Use appropriate path triggers
4. Include comprehensive error handling
5. Add to this README

### Modifying Existing Workflows

1. Test changes in a feature branch
2. Update this README if needed
3. Ensure backward compatibility
4. Consider impact on CI/CD pipeline

### Disabling Workflows

To disable a workflow temporarily:

```bash
git mv .github/workflows/workflow-name.yml .github/workflows/workflow-name.yml.disabled
```

## 📊 Monitoring

### Workflow Status

Monitor workflow status in the GitHub Actions tab:
- Green checkmark: ✅ All checks passed
- Red X: ❌ One or more checks failed
- Yellow dot: ⏳ Workflow in progress

### Artifacts

Workflows generate artifacts for analysis:
- Test results and coverage reports
- Security scan reports
- Dependency analysis reports
- Build artifacts

### Notifications

Configure notifications in GitHub repository settings:
- Email notifications for workflow failures
- Slack/Discord integration
- Custom webhook notifications

## 🛠️ Troubleshooting

### Common Issues

1. **Workflow not triggering:**
   - Check path filters
   - Verify branch names
   - Ensure files are in correct directories

2. **Build failures:**
   - Check Go version compatibility
   - Verify dependency versions
   - Review error logs

3. **Linting failures:**
   - Run `go fmt` locally
   - Check golangci-lint configuration
   - Review linting rules

4. **Security scan failures:**
   - Review security warnings
   - Update vulnerable dependencies
   - Fix code security issues

### Local Testing

Test workflows locally before pushing:

```bash
# Test Go build
go build ./...

# Test linting
golangci-lint run

# Test formatting
go fmt ./...
goimports -w .
gofumpt -w .

# Test security
gosec ./...

# Test dependencies
go mod tidy
go mod verify
```

## 📈 Performance Optimization

### Caching

Workflows use GitHub Actions caching for:
- Go modules
- Build artifacts
- Test results

### Parallel Execution

Workflows are designed to run in parallel when possible:
- Matrix strategies for concurrent testing
- Independent job execution
- Optimized step ordering

### Resource Usage

- **Runners:** Ubuntu latest
- **Timeout:** 5-10 minutes per job
- **Concurrency:** Limited to prevent resource exhaustion

## 🔄 Maintenance

### Regular Tasks

1. **Weekly:**
   - Review security scan results
   - Check dependency updates
   - Monitor workflow performance

2. **Monthly:**
   - Update Go version support
   - Review and update linting rules
   - Optimize workflow configurations

3. **Quarterly:**
   - Review and update security tools
   - Assess workflow effectiveness
   - Plan improvements

### Version Updates

When updating Go versions:
1. Update workflow files
2. Test with new version
3. Update documentation
4. Monitor for compatibility issues

## 📚 Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Go Best Practices](https://golang.org/doc/effective_go.html)
- [golangci-lint Configuration](https://golangci-lint.run/usage/configuration/)
- [gosec Security Scanner](https://github.com/securecodewarrior/gosec)
- [Trivy Vulnerability Scanner](https://aquasecurity.github.io/trivy/)
