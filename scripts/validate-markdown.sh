#!/bin/sh
# Markdown validation helper script

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
readonly SCRIPT_VERSION

echo "Starting validate-markdown.sh v$SCRIPT_VERSION"
cd "$(dirname "$0")/.." || exit

echo "Running markdown validation..."

# Check if tools are available
if ! command -v markdownlint >/dev/null 2>&1; then
    echo "❌ markdownlint not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

if ! command -v prettier >/dev/null 2>&1; then
    echo "❌ prettier not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

# Run markdownlint
echo "🔍 Running markdownlint..."
if markdownlint "**/*.md" --ignore node_modules; then
    echo "✅ markdownlint passed"
else
    echo "❌ markdownlint found issues"
    echo "💡 Run 'markdownlint \"**/*.md\" --ignore node_modules --fix' to auto-fix"
    exit 1
fi

# Run prettier check
echo "🔍 Checking prettier formatting..."
if prettier --check "**/*.md" --ignore-path .gitignore; then
    echo "✅ prettier formatting is correct"
else
    echo "❌ prettier found formatting issues"
    echo "💡 Run 'prettier --write \"**/*.md\" --ignore-path .gitignore' to auto-fix"
    exit 1
fi

echo "✅ All markdown validation passed!"
