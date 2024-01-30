#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-prefetch -p curl -p jq
# shellcheck shell=bash

set -exuo pipefail

latest_tag=$(curl https://api.github.com/repos/klzgrad/naiveproxy/releases/latest | jq --raw-output .tag_name)
latest_hash=$(nix-prefetch fetchFromGitHub --owner "klzgrad" --repo "naiveproxy" --rev "$latest_tag")

sed -i "/^  version = .*;/c\  version = \"${latest_tag#v}\";" ./default.nix
sed -i "/^    sha256 = .*;/c\    sha256 = \"${latest_hash}\";" ./default.nix
