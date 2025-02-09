#! /usr/bin/env nix
#! nix shell nixpkgs#starship --command /bin/sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCIPT_DIR"

install -m644 $(dirname $(dirname $(which starship)))/share/starship/presets/*.toml presets/
