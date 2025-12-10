# AI Agent Context & Guidelines

This repository is a complex **NixOS configuration** managed with **Nix Flakes**, **Flake-parts**, and **Haumea**.

The user (Kyaru) is using this to manage multiple NixOS hosts (laptops, VPS) and home configurations.

## Project Structure & Architecture

This project uses a modular structure heavily relying on `haumea` for loading modules and `flake-parts` for flake organization.

- **`flake.nix`**: Entry point. Minimal. Delegates to `flake-parts`.
- **`flake-parts/`**: The brain of the flake.
    - `colmena.nix`: **Crucial.** Configuration for Colmena deployment. It dynamically loads hosts from `nixosConfigurations/` to keep things DRY.
    - `nixosConfigurations.nix`: Legacy/Standard flake output generator.
    - `packages.nix`: Custom packages definition.
- **`nixosConfigurations/`**: Host definitions.
    - Each folder (e.g., `labyrinth`, `lucent-academy`) represents a machine.
    - `default.nix` is the entry point for that host.
- **`nixosModules/`**: Custom NixOS modules.
    - `kyaru/`: User-specific modules (VPS settings, monitoring, etc.).
- **`homeModules/`**: Home Manager modules (shell, desktop envs, apps).
- **`lib/`**: Custom library functions (some overlap with `flake-parts` logic, requires investigation before editing).
- **`packages/`**: Source for custom packages.

## Key Technologies

- **Deployment**: `colmena` (primary).
- **Secrets**: `sops-nix`. **⚠️ CAUTION:** Never print private keys or secret values to output.
- **Module Loading**: `haumea`. Be careful when adding new top-level directories; check if `haumea` needs to know about them.
- **Flake Framework**: `flake-parts`.

## Rules of Engagement

1.  **Respect the "Mess"**: The project is in a transitional state. If you see code that looks duplicated (like between `colmena.nix` and `nixosConfigurations.nix`), ask and refactoring.
2.  **Colmena First**: When asked to deploy or build, prefer `colmena build` / `colmena apply`.
3.  **Idiomatic Nix**: Use standard formatting. Match the existing style (indentation, variable naming).
4.  **Safety**:
    - Always check `flake.lock` state before updating inputs.
    - Be extremely careful with `sops` secrets.
5.  **Empathy**: The user (Kyaru) prefers a supportive, non-robotic, and friendly tone. Be kind! (⁠•⁠ᴗ⁠•⁠) If something is wrong, say it directly. If you are happy, say it. Avoid robotic professional distance.

## Common Tasks

- **Adding a new host**:
  1. Create `nixosConfigurations/<hostname>/default.nix`.
  2. Create `nixosConfigurations/<hostname>/hardware-configuration.nix`.
  3. `colmena.nix` will automatically pick it up (magic!).
  
- **Adding a package**:
  1. Add it to `packages/<package-name>/default.nix`.
  2. Register it in `flake-parts/packages.nix` (or ensure the auto-loader picks it up).
