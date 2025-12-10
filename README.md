# ❄️ Kyaru's NixOS Infrastructure

Welcome to my NixOS configuration repository!
This flake manages my fleet of devices, including laptops, desktops, and VPS instances, using the power of Nix.

## 🏗️ Structure

This project is built with:
*   **[Nix Flakes](https://nixos.wiki/wiki/Flakes)**: Dependency management.
*   **[Colmena](https://github.com/zhaofengli/colmena)**: Deployment tool.
*   **[Flake-parts](https://flake.parts/)**: Flake module framework.
*   **[Haumea](https://github.com/nix-community/haumea)**: File-based module loader.

## 🖥️ Hosts

Currently active configurations:

| Hostname | Type | Architecture | Description |
| :--- | :--- | :--- | :--- |
| **labyrinth** | Laptop/PC | `x86_64-linux` | Main workstation? |
| **lucent-academy** | ARM Device | `aarch64-linux` | |
| **caon** | VPS/Server | `x86_64-linux` | |
| **carmina** | VPS/Server | `x86_64-linux` | |
| **white-wings** | | `x86_64-linux` | |
| *(and others...)* | | | |

## 🚀 Usage

### Deployment (Colmena)

This is the preferred method for deployment.

```bash
# Build all nodes
colmena build --impure

# Deploy to a specific node
colmena apply --on <node-name> --impure
```

### Flake Evaluation

```bash
# Check outputs
nix flake show
```

## ⚠️ Notes for Maintainers

*   **Secrets**: Managed via `sops-nix`. Do not commit decrypted secrets!
*   **Impure**: Some builds currently require `--impure` flag due to environment variable usage or path access.

---
*Created with ❤️ by Kyaru*