#!/usr/bin/env bash
set -euo pipefail
set -x
git config filter.git-sops.required true
git config filter.git-sops.smudge 'sops --decrypt --path %f /dev/stdin'
git config filter.git-sops.clean 'scripts/git-sops-clean.sh %f'
