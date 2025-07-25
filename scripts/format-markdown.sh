#!/bin/sh
# Markdown formatting helper script

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

echo "Starting format-markdown.sh v$SCRIPT_VERSION"
cd "$(dirname "$0")/.." || exit

echo "Formatting markdown files..."

# Check if tools are available
if ! command -v markdownlint >/dev/null 2>&1; then
    echo "❌ markdownlint not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

if ! command -v prettier >/dev/null 2>&1; then
    echo "❌ prettier not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

# Auto-fix with markdownlint
echo "🔧 Auto-fixing with markdownlint..."
markdownlint "**/*.md" --ignore node_modules --fix

# Format with prettier
echo "🔧 Formatting with prettier..."
prettier --write "**/*.md" --ignore-path .gitignore

echo "✅ Markdown formatting complete!"
