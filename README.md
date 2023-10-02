# KiruyaMomochi's Nix config

## TODO

- [ ] Make sops use the same iv when encrypting an existing file.
- [ ] Find a way to [customize sops diff](https://git-scm.com/docs/gitattributes#_customizing_word_diff)
- [ ] Try to import secrets, but ignore them if not decrypted.
  See <https://github.com/vlaci/nixos-config/blob/main/modules/nixos/secrets.nix>.
- [ ] Better method to handle secrets in naiveproxy.
- [ ] Recursively `mapModule`.
- [ ] Monitor S3 usage.
- [ ] Move Telegraf to a custom module.
- [ ] Add Log monitoring.
- [ ] Add `mapPackage` function that do not use `default.nix` as package name, but `package.nix` instead, following [Name-based package directories](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/README.md#name-based-package-directories).

## References

- [hlissner/dotfiles](https://github.com/hlissner/dotfiles)
