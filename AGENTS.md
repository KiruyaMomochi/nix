# AI Agent Context & Guidelines

This repository is a **NixOS configuration** managed with **Nix Flakes** and **flake-parts**.

The user (Kyaru) uses it to manage multiple NixOS hosts (laptops, VPS) and Home Manager configurations. This is the **public** half: real deployments always go through the private flake `../nix-kyaru-secret`, which imports this one as the `nix-kyaru` input and layers secrets and host-private settings on top.

## Project Structure & Architecture

Directories are discovered automatically by `load-tree.nix` (a small in-repo loader). Files or directories starting with `_` are skipped; a `foo.nix` next to a `foo/` directory is an error.

- **`flake.nix`**: Entry point. Minimal. Delegates to `flake-parts`.
- **`flake-parts/`**: Flake outputs.
    - `default.nix`: Loads `lib/`, `nixosModules/`, `homeModules/` via `load-tree.nix`.
    - `nixosConfigurations.nix`: One `nixosConfiguration` per directory in `nixosConfigurations/` (via `lib/nixos.nix`).
    - `homeConfigurations.nix`: Base profiles (`kyaru`, `kyaru-desktop`, `kyaru-headless`) plus per-host homes from `homeConfigurations/`.
    - `packages.nix`: Custom packages (auto-collected by `lib/packages.nix`).
- **`nixosConfigurations/`**: Host definitions. Each folder (e.g., `caon`, `labyrinth`, `lucent-academy`) is a machine; `default.nix` is its entry point.
- **`nixosModules/`**: Custom NixOS modules. `kyaru/` holds user-specific modules (VPS settings, monitoring, etc.).
- **`homeModules/`**: Home Manager modules (shell, desktop envs, apps).
- **`lib/`**: Helper functions used by `flake-parts/` (`mkHost`, `loadHosts`, `mkHome`, `mkPackages`, ...).
- **`packages/`**: Source for custom packages.

## Key Technologies

- **Deployment**: `nixos-rebuild` / `home-manager`, run from `../nix-kyaru-secret` (`just deploy-nixos <host>`, `just home`). Building or switching straight from this repo drops all the secret-layer settings.
- **Secrets**: `sops-nix`, configured in the private flake. **⚠️ CAUTION:** Never print private keys or secret values to output.
- **Module Loading**: `load-tree.nix`. New files under `nixosModules/`, `homeModules/`, `lib/` are picked up automatically once they are `git add`ed.
- **Flake Framework**: `flake-parts`.

## Rules of Engagement

1.  **Public repo**: This is published on GitHub. Keep comments and commit messages technical; IPs, credentials and private toggles belong in `../nix-kyaru-secret`.
2.  **Lock propagation**: After changing this repo, run `nix flake update nix-kyaru` in `../nix-kyaru-secret`, or the secret flake keeps building the old snapshot.
3.  **Idiomatic Nix**: Use standard formatting (`nixpkgs-fmt`). Match the existing style (indentation, variable naming).
4.  **Safety**:
    - Always check `flake.lock` state before updating inputs.
    - Be extremely careful with `sops` secrets.
5.  **Empathy**: The user (Kyaru) prefers a supportive, non-robotic, and friendly tone. Be kind! (⁠•⁠ᴗ⁠•⁠) If something is wrong, say it directly. If you are happy, say it. Avoid robotic professional distance.

## Common Tasks

- **Adding a new host**:
  1. Create `nixosConfigurations/<hostname>/default.nix`.
  2. Create `nixosConfigurations/<hostname>/hardware-configuration.nix`.
  3. `git add` them; `flake-parts/nixosConfigurations.nix` picks the directory up automatically. Host secrets go in `../nix-kyaru-secret/hosts/<hostname>.nix`.

- **Adding a package**:
  1. Add it to `packages/<package-name>/default.nix`.
  2. `git add` it; `lib/packages.nix` collects it into `packages.<system>`.
