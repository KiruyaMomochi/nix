{ self, super, inputs, lib, ... }:
let
  inherit (lib.attrsets) filterAttrs;
  inherit (super.packages) mkPkgs;

  homeManagerConfiguration = inputs.home-manager.lib.homeManagerConfiguration;
  defaultSystem = "x86_64-linux";
in
{
  makeOverridableHomeManagerConfig = config:
    (homeManagerConfiguration config) // {
      override = f: self.makeOverridableHomeManagerConfig (config // f config);
    };
  # TODO: use flake-parts pkgs
  mkHome = attrs @ { system ? defaultSystem, ... }:
    self.makeOverridableHomeManagerConfig {
      pkgs = mkPkgs inputs.nixpkgs system;
      extraSpecialArgs = {
        inherit inputs;
      };
      modules = [
        {
          nixpkgs.overlays = [ inputs.self.overlays.default ];
        }
        inputs.vscode-server.nixosModules.home
        inputs.nix-index-database.homeModules.nix-index
        (filterAttrs (name: value: name != "system") attrs)
        ../home.nix
      ] ++ (inputs.nixpkgs.lib.attrValues inputs.self.homeModules);
    };
}
