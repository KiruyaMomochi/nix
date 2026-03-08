#!/usr/bin/env nix
#!nix shell nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#nurl nixpkgs#gnused --command bash
# shellcheck shell=bash

set -xeuo pipefail

# Find the directory of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR" || exit

# Get the latest commit of the cronet-go branch
latest_commit=$(curl -s https://api.github.com/repos/SagerNet/naiveproxy/commits/cronet-go | jq -r .sha)

# Update the default.nix file to use lib.fakeHash
sed -i -e "s/rev = \".*\";/rev = \"$latest_commit\";/" ./default.nix
sed -i -e "s|hash = \".*\";|hash = lib.fakeHash;|" ./default.nix

# Fetch new hash using nurl (it will fail with the correct hash, so we disable set -e temporarily)
set +e
nixpkgs=$(nix eval -I "nixpkgs=flake:github:nixos/nixpkgs" --expr '<nixpkgs>' --impure)
new_hash=$(nurl -e "((import ${nixpkgs} {}).callPackage ./default.nix {})")
set -e

if [ -n "$new_hash" ]; then
	sed -i -e "s|hash = lib.fakeHash;|hash = \"$new_hash\";|" ./default.nix
	echo "Updated libcronet-naive to $latest_commit with hash $new_hash"
else
	echo "Failed to get new hash"
	exit 1
fi
