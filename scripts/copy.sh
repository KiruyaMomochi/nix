#!/usr/bin/env bash
set -uxo pipefail

SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
error_occurred=0

if [ $# -gt 0 ]; then
    targets=("$@")
else
    mapfile -t targets < "$SCRIPT_DIR/targets.txt"
fi
for target in "${targets[@]}"; do
  echo "::group::$target"
  normalized_target="${target//#/}"
  normalized_target="${normalized_target//./}"
  nix run github:Mic92/nix-fast-build -- --skip-cached --no-nom --flake "$target" --copy-to "s3://nix-cache?scheme=https&endpoint=usc1.contabostorage.com&secret-key=$(realpath ~/.config/nix/secret-key)"
  # nix copy --print-build-logs --to 's3://nix-cache?scheme=https&endpoint=usc1.contabostorage.com&secret-key='$(realpath ~/.config/nix/secret-key) "$target" | tee "$normalized_target.log"
  result=$?
  if [ $result -ne 0 ]; then
    echo "::error title=build failed ($result)::$target"
    error_occurred=1
  fi
  echo "::endgroup::"
done

exit "$error_occurred"
