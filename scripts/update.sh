#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Running nix flake update..."
nix flake update --commit-lock-file

if git diff --name-only | grep -q "flake.lock"; then
    echo "✅ Flake lockfile updated."
    
    echo "## Flake Update Report" > update-report.md
    echo "" >> update-report.md
    echo "Updates the following inputs:" >> update-report.md
    echo "" >> update-report.md
    
    git diff flake.lock | grep 'rev =' | sed 's/^[ 	]*//' >> update-report.md
    
    echo "📝 Update report generated in update-report.md"
else
    echo "✨ No updates available."
fi
