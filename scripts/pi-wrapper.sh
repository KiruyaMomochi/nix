#!/usr/bin/env bash
# pi-coding-agent wrapper
#
# - nodejs_22: pi needs npm on PATH for `npm root -g` etc.
# - NPM_CONFIG_PREFIX: writable location for `pi install npm:...`
# - ~/kaoru/bin: xdg-open shim (WSL only, native Linux has xdg-open)

export NPM_CONFIG_PREFIX="${HOME}/.local/share/pi-npm"

# WSL: prepend ~/kaoru/bin for the xdg-open shim that hands URLs to Windows
if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop || -n "${WSL_DISTRO_NAME:-}" ]]; then
  export PATH="${HOME}/kaoru/bin:${PATH}"
fi

exec nix shell nixpkgs#nodejs_22 github:numtide/llm-agents.nix#pi -c pi "$@"
