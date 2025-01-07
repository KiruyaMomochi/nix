{ self, super, root, ... }: { inputs, ... }: {
  flake = {
    # https://github.com/nix-community/home-manager/pull/3969
    homeConfigurations =
      let
        # TODO: is it possible to make it contains self?
        # inherit (lib.fixedPoints) extends;
        # makeOverridableHomeManagerConfig
        homeManagerConfiguration = inputs.home-manager.lib.homeManagerConfiguration;
        makeOverridableHomeManagerConfig = config:
          (homeManagerConfiguration config) // {
            override = f: makeOverridableHomeManagerConfig (config // f config);
          };
        # TODO: use flake-parts pkgs
        mkPkgs = pkgs: system: import pkgs {
          inherit system;
          config = import ../../nixpkgs-config.nix;
          overlays = [ inputs.self.overlays.default ];
        };
      in
      rec {
        kyaru = kyaru-headless;
        kyaru-headless = makeOverridableHomeManagerConfig {
          pkgs = mkPkgs inputs.nixpkgs "x86_64-linux";
          extraSpecialArgs = {
            inherit inputs;
            lib-kyaru = { };
          };
          modules = [
            inputs.vscode-server.nixosModules.home
            inputs.nix-index-database.hmModules.nix-index
            ../../home.nix
          ] ++ (inputs.nixpkgs.lib.attrValues inputs.self.homeModules);
        };
        kyaru-desktop = kyaru-headless.override (oldConfig: {
          modules = oldConfig.modules ++ [{
            programs.kyaru = {
              desktop.enable = true;
              kde.enable = true;
            };
          }];
        });
      };
  };
}
