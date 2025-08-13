#!/usr/bin/env python3
import re

# Read the file
with open("Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh", "r") as f:
    content = f.read()

# Fix the problematic tr commands that have embedded newlines
# Pattern 1: tr -d with embedded newlines in cellular monitoring
content = re.sub(
    r"(\| tr -d ')([^']*\n[^']*)(,' \| head -c \d+\))",
    r"\1\\n\\r\3",
    content,
    flags=re.MULTILINE,
)

# Also fix sed pattern that's broken
content = re.sub(
    r'(sed \'s/\.\*"\\(\[^\^"]\*\\)"\.\*/)/(\' \| tr)', r"\1\\1/' | tr", content
)

# Write the fixed content back
with open("Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh", "w") as f:
    f.write(content)

print("Fixed quote issues in the shell script")
