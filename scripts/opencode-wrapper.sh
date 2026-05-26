#!/usr/bin/env bash
exec nix shell github:numtide/llm-agents.nix#opencode -c opencode "$@"
