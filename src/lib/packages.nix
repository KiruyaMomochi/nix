{ inputs, lib, ... }:
let
  inherit (lib.lists) foldl;
  inherit (lib.kyaru.modules) mapModules;
in
{
  mkPkgs = pkgs: system: import pkgs {
    inherit system;
    config = import ../../nixpkgs-config.nix;
    # overlays = [ inputs.self.overlays.default ];
  };

  mapPackages = pkgs: overrides: foldl (a: b: a // b) { } [
    (mapModules ../packages (p: pkgs.callPackage p overrides))
    (mapModules ../packages/qt5 (p: pkgs.libsForQt5.callPackage p overrides))
    # (mapModules ../packages/chromium (p: pkgs.chromium.callPackage p { }))
  ];
}
