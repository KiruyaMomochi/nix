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
  normalized_target="${target//#/}"
  normalized_target="${normalized_target//./}"
  cmd=(
    nix 
    run 
    github:Mic92/nix-fast-build 
    -- 
    --skip-cached
  )
  if ! [ -t 1 ]; then
    cmd+=(--no-nom)
  fi
  cmd+=(
    --flake "$target"
    --copy-to "s3://nix-cache?scheme=https&endpoint=usc1.contabostorage.com&secret-key=$(realpath ~/.config/nix/secret-key)"
  )
  "${cmd[@]}" | tee "$normalized_target.log" | grep -e "error:" -e "pattern:"
  result=$?
  if [ $result -ne 0 ]; then
    echo "::error title=build failed ($result)::$target"
    while IFS= read -r drv; do
    echo "::error $target::$drv"
      echo "::group::$target::$drv"
      nix log "$drv"
      echo "::endgroup::"
    done < <( grep -oP "nix log \K[^']+" "$normalized_target.log" )
    error_occurred=1
  fi
done

exit "$error_occurred"
