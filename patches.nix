# Patching nixpkgs
# See https://github.com/NixOS/nix/issues/3920
# Each elements will be called by fetchpatch
[
  {
    url = "https://patch-diff.githubusercontent.com/raw/NixOS/nixpkgs/pull/425384.diff";
    sha256 = "sha256-VJT5YJ/Gyew5j1nE5Q2+gZo83NZtkqCG4wrOMOYcf+s=";
  }
]
