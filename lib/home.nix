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
        }
        inputs.vscode-server.homeModules.default
        inputs.nix-index-database.homeModules.nix-index
        inputs.zen-browser.homeModules.twilight
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
      raw = (import ../load-tree.nix { inherit lib; }) {
        inherit src;
        defaultOnly = true;
        transform = cursor: module:
          if cursor == [ ] then module
          else if builtins.length cursor == 1 then module.default or null
          else null;
      };

      # Rename keys: add "kyaru@" prefix when no "@" present
      toKey = name: if hasInfix "@" name then name else "kyaru@${name}";
    in
    lib.mapAttrs' (name: value: lib.nameValuePair (toKey name) value) raw;
}
