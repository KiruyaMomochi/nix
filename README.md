# Kyaru's NixOS Infrastructure

Welcome to my NixOS configuration repository!
This flake manages my fleet of devices, including laptops, desktops, and VPS instances, using the power of Nix.

## Structure

This project is built with:
*   **[Nix Flakes](https://nixos.wiki/wiki/Flakes)**: Dependency management.
*   **[Colmena](https://github.com/zhaofengli/colmena)**: Deployment tool.
*   **[Flake-parts](https://flake.parts/)**: Flake module framework.
*   **[Haumea](https://github.com/nix-community/haumea)**: File-based module loader.

## Hosts

Currently active configurations:

| Hostname | Type | Architecture | Description |
| :--- | :--- | :--- | :--- |
| **labyrinth** | Laptop/PC | `x86_64-linux` | Main workstation? |
| **lucent-academy** | ARM Device | `aarch64-linux` | |
| **caon** | VPS/Server | `x86_64-linux` | |
| **carmina** | VPS/Server | `x86_64-linux` | |
| **white-wings** | | `x86_64-linux` | |
| *(and others...)* | | | |

## Usage

### Updating Flake Inputs

When changes are made to local path inputs (like `nix-kyaru-secret`), or to refresh external dependencies, run:

```bash
nix flake update
```

### Deployment (Colmena)

This is the preferred method for deployment.

```bash
# Build all nodes
colmena build --impure

# Deploy to a specific node
colmena apply --on <node-name> --impure
```

## Continuous Integration (CI)

This flake utilizes GitHub Actions for continuous integration, defined in `.github/workflows/ci.yml`. The CI pipeline is designed to:

-   **Validate Flake**: Automatically check the flake's health and consistency.
-   **Build & Cache**: Build various flake outputs (packages, NixOS configurations, home configurations) and push them to a shared S3 cache. This significantly speeds up subsequent deployments and local builds.
-   **Disk Space Management**: To address GitHub Runner's limited disk space, the build process is split into multiple independent jobs, each with aggressive disk cleanup. This allows large NixOS configurations to be built without `no space left` errors.

## Notes for Maintainers

*   **Secrets**: Managed via `sops-nix`. Do not commit decrypted secrets!
*   **Impure**: Some builds currently require `--impure` flag due to environment variable usage or path access.
