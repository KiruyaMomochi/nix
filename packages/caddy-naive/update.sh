#!/usr/bin/env nix
#!nix shell nixpkgs#bash nixpkgs#go nixpkgs#nurl --command bash
# shellcheck shell=bash

set -xeuo pipefail

tempdir=$(mktemp -d --suffix caddy-naive)
src=$(nix build github:nixos/nixpkgs#caddy.src --no-link --print-out-paths)

pushd "$tempdir" || exit
cp -r --no-preserve=mode "$src/." .
sed -i -e '\!// plug in Caddy modules here!a _ "github.com/caddyserver/forwardproxy"' ./cmd/caddy/main.go
go mod edit -replace github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive
go mod tidy -e
go mod vendor
popd || exit

cp -r "$tempdir/go.mod" "$tempdir/go.sum" .

# nix build .#caddy-naive --no-link -L

nixpkgs=$(nix eval -I "nixpkgs=flake:github:nixos/nixpkgs" --expr '<nixpkgs>' --impure)
oldHash=$(nix eval --impure --raw --expr "((import ${nixpkgs} {}).callPackage ./default.nix {}).vendorHash")
newHash=$(nurl -e "((import ${nixpkgs} {}).callPackage (import ./default.nix) { } ).goModules")
echo "${oldHash} -> ${newHash}"
sed -i "s|vendorHash = \"${oldHash}\"|vendorHash = \"${newHash}\"|" ./default.nix
