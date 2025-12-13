{
  description = "Extended flake from kyaru";

  inputs = {
    nix-kyaru.url = "github:KiruyaMomochi/nix";
    nixpkgs.follows = "nix-kyaru/nixpkgs";
  };

  outputs = { self, nix-kyaru, nixpkgs }:
    let
      inherit (lib.attrsets) mapAttrs recursiveUpdate;
      inherit (lib.lists) foldl;
      inherit (lib.kyaru.modules) mapModulesRecursive;

      mkPkgs = pkgs: system: import pkgs {
        inherit system;
        config = import ./nixpkgs-config.nix;
      };
      lib = nix-kyaru.lib;
      recursiveUpdateAll = foldl recursiveUpdate { };
    in
    nix-kyaru.outputs // {
      # https://determinate.systems/posts/extending-nixos-configurations
      nixosConfigurations =
        let
          hosts = mapModulesRecursive ./hosts import;
        in
        mapAttrs
          (
            name: value: value.extendModules {
              modules = [
                hosts.${name}
              ];
            }
          )
          nix-kyaru.outputs.nixosConfigurations;

      homeConfigurations =
        mapAttrs
          (
            name: value: value.override (super: {
              pkgs = mkPkgs nixpkgs super.pkgs.stdenv.hostPlatform.system;
              modules = super.modules ++ [
                ./home.nix
              ];
            })
          )
          nix-kyaru.outputs.homeConfigurations;

      deploy.nodes =
        recursiveUpdateAll [
          nix-kyaru.deploy.nodes
          (
            builtins.mapAttrs
              (name: value:
                let system = value.pkgs.stdenv.hostPlatform.system; in recursiveUpdateAll [
                  # Override the previous nixos
                  { profiles.system.path = self.deployPkgs.${system}.deploy-rs.lib.activate.nixos value; }
                ])
              self.nixosConfigurations
          )
        ];
      # https://github.com/serokell/deploy-rs/issues/78 password based sudo
      deploy.magicRollback = false;
    };
}
