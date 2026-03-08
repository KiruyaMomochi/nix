#!/usr/bin/env nix
#!nix shell nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#nurl nixpkgs#gnused --command bash
# shellcheck shell=bash

set -xeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "$DIR/../.." >/dev/null 2>&1 && pwd)"
cd "$DIR" || exit

# 1. Get latest version of SagerNet/sing-box
version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/^v//')

# Update version in default.nix
sed -i -e "s/version = \".*\";/version = \"$version\";/" ./default.nix

# 2. Get source hash using nurl and lib.fakeHash
sed -i -e "s|hash = \".*\";|hash = lib.fakeHash;|" ./default.nix

set +e
nixpkgs=$(nix eval -I "nixpkgs=flake:github:nixos/nixpkgs" --expr '<nixpkgs>' --impure)
new_hash=$(nurl -e "(let pkgs = import ${nixpkgs} {}; in pkgs.callPackage ./default.nix { kyaru = { libcronet-naive = pkgs.callPackage ${ROOT_DIR}/packages/libcronet-naive {}; }; }).src")
set -e

if [ -n "$new_hash" ]; then
	sed -i -e "s|hash = lib.fakeHash;|hash = \"$new_hash\";|" ./default.nix
else
	echo "Failed to get source hash"
	exit 1
fi

# 3. Get vendorHash using nurl
sed -i -e "s|vendorHash = \".*\";|vendorHash = lib.fakeHash;|" ./default.nix

set +e
new_vendor_hash=$(nurl -e "(let pkgs = import ${nixpkgs} {}; in pkgs.callPackage ./default.nix { kyaru = { libcronet-naive = pkgs.callPackage ${ROOT_DIR}/packages/libcronet-naive {}; }; }).goModules")
set -e

if [ -n "$new_vendor_hash" ]; then
	sed -i -e "s|vendorHash = lib.fakeHash;|vendorHash = \"$new_vendor_hash\";|" ./default.nix
	echo "Successfully updated sing-box-naive to version $version, hash $new_hash, vendorHash $new_vendor_hash"
else
	echo "Failed to get vendorHash. You might need to check if sing-box upstream is broken."
	exit 1
fi
