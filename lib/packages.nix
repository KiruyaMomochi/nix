{ inputs, lib, ... }:
let
  inherit (lib.lists) foldl;
  inherit (lib.kyaru.modules) mapModules;
in
{
  mapPackages = pkgs: foldl (a: b: a // b) { } [
    (mapModules ../packages (p: pkgs.callPackage p { }))
    (mapModules ../packages/qt5 (p: pkgs.libsForQt5.callPackage p { }))
    # (mapModules ../packages/chromium (p: pkgs.chromium.callPackage p { }))
  ];
}
