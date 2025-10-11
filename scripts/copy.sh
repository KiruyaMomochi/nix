#!/usr/bin/env bash
set -uxo pipefail

SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
error_occurred=0

if [ -z "${istty:-}" ]; then
  if [ -t 1 ]; then
    istty=1
  else
    istty=0
  fi
fi

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
  if [ "$istty" -lt 1 ]; then
    cmd+=(--no-nom)
  fi
  cmd+=(
    --flake "$target"
    --copy-to "s3://nix-cache?scheme=https&endpoint=usc1.contabostorage.com&secret-key=$(realpath ~/.config/nix/secret-key)"
  )
  if [ "$istty" -lt 1 ]; then
    echo "target: $target"
    "${cmd[@]}" 2>&1 >"$normalized_target.out.log" | tee "$normalized_target.err.log" | grep -e "error:"
    result="${PIPESTATUS[0]}"
  else
    "${cmd[@]}"
    result="$?"
  fi
  if [ $result -ne 0 ] && [ "$istty" -lt 1 ]; then
    echo "::error title=build failed ($result)::$target"
    while IFS= read -r drv; do
      echo "::error $target::$drv"
      echo "::group::$target::$drv"
      nix log "$drv"
      echo "::endgroup::"
    done < <( grep -oP "nix log \K[^']+" "$normalized_target.out.log" )
    error_occurred=1
  fi
done

exit "$error_occurred"
