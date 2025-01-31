#!/usr/bin/env bash
set -x

SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
mapfile -t targets < "$SCRIPT_DIR/targets.txt"
for target in "${targets[@]}"; do
  echo "::group::$target"
  nix copy --print-build-logs --to 's3://nix-cache?scheme=https&endpoint=usc1.contabostorage.com&secret-key='$(realpath ~/.config/nix/secret-key) "$target"
  echo "::endgroup::"
done
