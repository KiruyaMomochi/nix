{ inputs, lib, ... }:
let
  inherit (lib.lists) foldl;
  inherit (lib.kyaru.modules) mapModules;
in
{
  mkPkgs = pkgs: system: import pkgs {
    inherit system;
    config = import ../nixpkgs-config.nix;
    # overlays = [ inputs.self.overlays.default ];
  };
  
  mkPkgsWithConfig = pkgs: system: extraConfig: import pkgs {
    inherit system;
    config = (import ../nixpkgs-config.nix) // extraConfig;
  };

  mapPackages = pkgs: overrides: foldl (a: b: a // b) { } [
    (mapModules ../packages (p: pkgs.callPackage p overrides))
    (mapModules ../packages/qt5 (p: pkgs.libsForQt5.callPackage p overrides))
    # (mapModules ../packages/chromium (p: pkgs.chromium.callPackage p { }))
  ];

  mkPackages =
    let
      mkCallPackaage = pkgs: set: {
        # default = a: b: (builtins.trace pkgs (pkgs.callPackage a b));
        default = pkgs.callPackage;
        qt5 = pkgs.libsForQt5.callPackage;
      }."${set}";

      # loader = attrs: path: (builtins.trace "path = ${path}" (haumea.lib.loaders.verbatim attrs path));
      # loader = attrs: path: (path);

      loader = attrs: path: (inputs.haumea.lib.loaders.verbatim attrs path);
      matcher = { inherit loader; matches = filename: filename == "default.nix"; };

      # find how to callPackage
      cursorToPackage = pkgs: cursor: package:
        let
          depth = builtins.length cursor;
          set = if depth == 0 then null else if depth == 1 then "default" else (builtins.elemAt cursor 0);
          callPackage = mkCallPackaage pkgs set;
        in
        {
          inherit package set callPackage;
        };

      # transformers
      moduleToPackageSpec = pkgs: cursor: module:
        # builtins.trace "depth = ${builtins.toString depth}, cursor = ${builtins.toString cursor}, set = ${builtins.toString set}"
        if module ? default then (cursorToPackage pkgs cursor module.default) else module;
      callEachPackage = cursor: module:
        if module ? package then (module.callPackage module.package { }) else module;
    in
    pkgs: inputs.haumea.lib.load {
      src = ../packages;
      loader = [ matcher ];
      transformer = [ (moduleToPackageSpec pkgs) callEachPackage ];
    };
}