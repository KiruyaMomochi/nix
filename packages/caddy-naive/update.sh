#!/usr/bin/env nix-shell
#!nix-shell -i bash -p go -p nix-prefetch
# shellcheck shell=bash

set -xeuo pipefail

tempdir=$(mktemp -d --suffix caddy-naive)
src=$(nix build nixpkgs#caddy.src --no-link --print-out-paths)

pushd "$tempdir" || exit
cp "$src/cmd/caddy/main.go" .
go mod init caddy
sed -i -e '\!// plug in Caddy modules here!a _ "github.com/caddyserver/forwardproxy"' ./main.go
go mod edit -replace github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive
go mod tidy
go mod vendor
popd || exit

cp -r "$tempdir/go.mod" "$tempdir/go.sum" .

oldHash=$(nix eval --impure --raw --expr '((import <nixpkgs> {}).callPackage ./default.nix {}).vendorHash')
newHash=$(nix-prefetch '{ sha256 }: (callPackage (import ./default.nix) { }).goModules.overrideAttrs (_: { outputHash = sha256; })')
echo "${oldHash} -> ${newHash}"
sed -i "s|vendorHash = \"${oldHash}\"|vendorHash = \"${newHash}\"|" ./default.nix
