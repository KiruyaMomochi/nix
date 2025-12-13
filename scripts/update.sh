#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Running nix flake update..."
nix flake update --commit-lock-file

# 如果 flake.lock 发生了变化
if git diff --name-only | grep -q "flake.lock"; then
    echo "✅ Flake lockfile updated."
    
    # 生成更新日志（这里我们可以简单利用 git log 或者 nix flake metadata，
    # 但为了简单通用，我们让它输出一段标准文本，CI 可以追加更多详情）
    echo "## Flake Update Report" > update-report.md
    echo "" >> update-report.md
    echo "Updates the following inputs:" >> update-report.md
    echo "" >> update-report.md
    
    # 尝试解析改动（比较简陋，但够用）
    git diff flake.lock | grep 'rev =' | sed 's/^[ 	]*//' >> update-report.md
    
    echo "📝 Update report generated in update-report.md"
else
    echo "✨ No updates available."
fi
