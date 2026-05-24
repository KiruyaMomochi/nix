{ self, super, inputs, lib, ... }:
let
  inherit (lib.attrsets) filterAttrs mapAttrs';
  inherit (lib.strings) hasInfix;
  inherit (super.packages) mkPkgs;

  homeManagerConfiguration = inputs.home-manager.lib.homeManagerConfiguration;
in
{
  makeOverridableHomeManagerConfig = config:
    (homeManagerConfiguration config) // {
      override = f: self.makeOverridableHomeManagerConfig (config // f config);
    };
  mkHome = { pkgs, ... }@attrs:
    self.makeOverridableHomeManagerConfig {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
      };
      modules = [
        {
          nixpkgs.overlays = [ inputs.self.overlays.default ];
        }
        inputs.vscode-server.nixosModules.home
        inputs.nix-index-database.homeModules.nix-index
        (filterAttrs (name: value: name != "pkgs") attrs)
        ../home.nix
      ] ++ (inputs.nixpkgs.lib.attrValues inputs.self.homeModules);
    };

  # Load per-machine home-manager overrides from homeConfigurations/ directory.
  # Directory name becomes the key:
  #   "caon"           → "kyaru@caon"   (auto-prefixed)
  #   "otheruser@host" → "otheruser@host" (used as-is)
  loadHomes = src:
    let
      loader = inputs.haumea.lib.loaders.verbatim;
      matcher = { inherit loader; matches = filename: filename == "default.nix"; };
      transformer = cursor: module:
        let
          depth = builtins.length cursor;
        in
        if depth == 0 then module
        else if depth == 1 then (module.default or null)
        else null;

      raw = inputs.haumea.lib.load {
        inherit src;
        loader = [ matcher ];
        transformer = [ transformer ];
      };

      # Rename keys: add "kyaru@" prefix when no "@" present
      toKey = name: if hasInfix "@" name then name else "kyaru@${name}";
    in
    lib.mapAttrs' (name: value: lib.nameValuePair (toKey name) value) raw;
}
