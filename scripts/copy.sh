#!/usr/bin/env bash
set -uxo pipefail

SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
error_occurred=0

mapfile -t targets < "$SCRIPT_DIR/targets.txt"
for target in "${targets[@]}"; do
  echo "::group::$target"
  normalized_target="${target//#/}"
  normalized_target="${normalized_target//./}"
  nix copy --print-build-logs --to 's3://nix-cache?scheme=https&endpoint=usc1.contabostorage.com&secret-key='$(realpath ~/.config/nix/secret-key) "$target" | tee "$normalized_target.log"
  result=$?
  if [ $result -ne 0 ]; then
    echo "::error title=build failed ($result)::$target"
    error_occurred=1
  fi
  echo "::endgroup::"
done

exit "$error_occurred"
