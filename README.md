# KiruyaMomochi's Nix config

## TODO

- [ ] Make sops use the same iv when encrypting an existing file.
- [ ] Find a way to [customize sops diff](https://git-scm.com/docs/gitattributes#_customizing_word_diff)
- [ ] Try to import secrets, but ignore them if not decrypted.
  See <https://github.com/vlaci/nixos-config/blob/main/modules/nixos/secrets.nix>.
- [ ] Auto set git filters:
  ```bash
  git config filter.git-sops.required true
  git config filter.git-sops.smudge 'sops --decrypt --path %f /dev/stdin'
  git config filter.git-sops.clean 'scripts/git-sops-clean.sh %f'
  ```
- [ ] Better method to handle secrets in naiveproxy.

## References

- [hlissner/dotfiles](https://github.com/hlissner/dotfiles)
