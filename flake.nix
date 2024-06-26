{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs";

    deploy-rs.url = "github:serokell/deploy-rs";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    # Fixes for vscode server under NixOS
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    # Windows subsystem for Linux support
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL?ref=22.05-5c211b47";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs@{ self, flake-utils, deploy-rs, ... }:
    let
      inherit (lib.kyaru.nixos) mapHosts;
      inherit (lib.kyaru.packages) mapPackages;
      inherit (lib.kyaru.modules) mapModules;
      inherit (lib.attrsets) attrValues optionalAttrs;

      mkPkgs = pkgs: system: import pkgs {
        inherit system;
        config = import ./nixpkgs-config.nix;
      };

      # https://github.com/NixOS/nixpkgs/pull/157056
      lib-kyaru = import ./lib { inherit inputs lib; };
      system = "x86_64-linux";

      # Patching nixpkgs
      # See https://github.com/NixOS/nix/issues/3920
      patches = [ ];

      originNixpkgs = inputs.nixpkgs;
      patchedNixpkgs =
        let
          originPkgs = originNixpkgs.legacyPackages.${system};
        in
        originPkgs.applyPatches {
          name = "nixpkgs-patched";
          src = inputs.nixpkgs;
          patches = map originPkgs.fetchpatch patches;
        };

      originLib = originNixpkgs.lib;
      # Copied from <nixpkgs>/flake.nix
      patchedLib = originLib.lists.foldl (a: b: a.extend b)
        (import (patchedNixpkgs + "/lib"))
        [
          (import (patchedNixpkgs + "/lib/flake-version-info.nix") self)
          (final: prev: {
            nixos = import (patchedNixpkgs + "/nixos/lib") { lib = final; };
            nixosSystem = args:
              import (patchedNixpkgs + "/nixos/lib/eval-config.nix") (
                {
                  lib = final;
                  # Allow system to be set modularly in nixpkgs.system.
                  # We set it to null, to remove the "legacy" entrypoint's
                  # non-hermetic default.
                  system = null;
                } // args
              );
          })
        ];

      nixpkgs = originNixpkgs;
      lib = originLib.extend (self: super: {
        kyaru = lib-kyaru;
      });
    in
    {
      inherit inputs lib;

      nixosConfigurations = mapHosts ./hosts { };

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
        in
        rec {
          kyaru = kyaru-headless;
          kyaru-headless = makeOverridableHomeManagerConfig {
            pkgs = mkPkgs nixpkgs system;
            extraSpecialArgs = { inherit inputs lib-kyaru; };
            modules = [
              inputs.vscode-server.nixosModules.home
              ./home.nix
            ] ++ (attrValues inputs.self.homeModules);
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

      nixosModules = mapModules ./modules import;

      deploy.nodes =
        let
          mkDeployConfig = nixos:
            let system = nixos.pkgs.system; in
            {
              hostname = nixos.config.networking.hostName;
              profiles.system = {
                user = "root";
                sshOpts = [ "-A" "-t" ];
                path = self.deployPkgs.${system}.deploy-rs.lib.activate.nixos nixos;
              } // (optionalAttrs (nixos.config.kyaru.vps.user ? name) { profiles.system.sshUser = nixos.config.kyaru.vps.user.name; });
            };
        in
        builtins.mapAttrs (_: mkDeployConfig)
          self.nixosConfigurations;

      homeModules = mapModules ./modules/home import;

      overlay = self.overlays.default;

      overlays = {
        default = (final: prev: rec {
          kyaru = mapPackages final { };
          slirp4netns = prev.slirp4netns.overrideAttrs (oldAttrs: {
            patches = (oldAttrs.patches or [ ]) ++ [
              ./packages/slirp4netns.patch
            ];
          });
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (
              python-final: python-prev: { }
            )
          ];
        });
      };

      templates = import ./templates;
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = mkPkgs nixpkgs system;
      in
      {
        pkgs =
          import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
            config = import ./nixpkgs-config.nix;
          };

        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            sops
            age
            ssh-to-age
            ssh-to-pgp
            jq
            yq
            vscode-langservers-extracted
            self.deployPkgs.${system}.deploy-rs.deploy-rs
          ];
        };
        packages = (mapPackages pkgs { });
        deployPkgs = import nixpkgs {
          inherit system;
          overlays = [
            deploy-rs.overlay
            (self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
          ];
        };
      }
    );

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://objects.kyaru.bond/nix-cache"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "kyaru-nix-cache-1:Zu6gS5WZt4Kyvi95kCmlKlSyk+fbIwvuuEjBmC929KM="
    ];
  };
}
