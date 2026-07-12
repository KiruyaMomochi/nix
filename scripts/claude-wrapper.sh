#!/usr/bin/env bash
exec nix shell github:numtide/llm-agents.nix#claude-code -c claude "$@"
