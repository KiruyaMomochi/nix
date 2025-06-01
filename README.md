# KiruyaMomochi's Nix config

For all my hosts see [hosts](hosts/README.md).

## Concept

* Entrypoint: [flake.nix](./flake.nix).
* Files are merged by [flake-parts](./src/flake-parts/default.nix).
* Each part are loaded by haumea. 

## TODO

- [ ] https://tailscale.com/kb/1320/performance-best-practices#ethtool-configuration
- [ ] Monitor S3 usage.
- [ ] Move Telegraf to a custom module.
- [ ] Add Log monitoring.
- [ ] Add `mapPackage` function that do not use `default.nix` as package name, but `package.nix` instead, following [Name-based package directories](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/README.md#name-based-package-directories).
- [ ] How to specify a package to dependend on another package under `packages/`?

## References

- [hlissner/dotfiles](https://github.com/hlissner/dotfiles)
- [pedorich-n/home-server-nixos](https://github.com/pedorich-n/home-server-nixos)

## Old way to handle sops secrets in-place

Using a .gitattributes file with the following cotent

```
hosts/**/secret.nix filter=git-sops diff=git-sops
```

And Git config

```toml
[filter "git-sops"]
    required = true
    smudge = sops --decrypt --path %f /dev/stdin
    clean = scripts/git-sops-clean.sh %f
```

And a custom sops (`self.packages.${system}.sops`).
