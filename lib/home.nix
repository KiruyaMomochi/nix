{ self, super, inputs, lib, ... }:
let
  inherit (lib.attrsets) filterAttrs;
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
}
