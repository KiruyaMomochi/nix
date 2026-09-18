#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#python3 --command bash
# shellcheck shell=bash

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Caddy follows flake.lock. Keep the forwardproxy pin explicit in default.nix;
# refresh this source hash after changing either version.
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT
expr='let f = builtins.getFlake (toString ./.);
  p = f.packages.${builtins.currentSystem}.caddy-naive;
  in p.src.overrideAttrs (_: {
    outputHash = f.inputs.nixpkgs.lib.fakeHash;
    impureEnvVars = [ "GOPROXY" "https_proxy" "http_proxy" "no_proxy" ];
  })'

if nix build --impure --no-link --expr "$expr" 2>"$tempdir/build.log"; then
  echo "Expected a fake-hash mismatch" >&2
  exit 1
fi
python3 - "$tempdir/build.log" packages/caddy-naive/default.nix <<'PY'
import pathlib
import re
import sys

log = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/]+=)", log)
if not match:
    sys.exit(log)
path = pathlib.Path(sys.argv[2])
text, count = re.subn(r'hash = "sha256-[A-Za-z0-9+/]+=";',
                      f'hash = "{match[1]}";', path.read_text(), count=1)
if count != 1:
    sys.exit("Expected exactly one plugin source hash in default.nix")
path.write_text(text)
print(f"Updated plugin source hash: {match[1]}")
PY
nix build .#caddy-naive --no-link
