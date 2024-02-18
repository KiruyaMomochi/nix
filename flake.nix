{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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

  outputs = inputs@{ self, nixpkgs, flake-utils, deploy-rs, ... }:
    let
      inherit (lib.kyaru.nixos) mapHosts;
      inherit (lib.kyaru.packages) mapPackages;
      inherit (lib.kyaru.modules) mapModules;

      mkPkgs = pkgs: system: import pkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };

      # https://github.com/NixOS/nixpkgs/pull/157056
      lib-kyaru = import ./lib { inherit inputs lib; };
      lib = nixpkgs.lib.extend (self: super: {
        kyaru = lib-kyaru;
      });

      patchednixpkgs =
        let
          patches = [
            {
              name = "plasma-6.patch";
              url = "https://patch-diff.githubusercontent.com/raw/NixOS/nixpkgs/pull/286522.patch";
              hash = "";
            }
          ];
          originPkgs = nixpkgs.legacyPackages."x86_64-linux";
        in
        originPkgs.applyPatches {
          name = "nixpkgs-patched";
          src = inputs.nixpkgs;
          patches = map originPkgs.fetchpatch patches;
        };
    in
    {
      inherit inputs;

      lib = lib-kyaru;

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
            pkgs = mkPkgs nixpkgs "x86_64-linux";
            extraSpecialArgs = { inherit inputs lib-kyaru; };
            modules = [ ./home.nix ];
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

      deploy.nodes = builtins.mapAttrs
        (name: value:
          let system = value.pkgs.system; in
          {
            hostname = value.config.networking.hostName;
            profiles.system = {
              user = "root";
              sshOpts = [ "-A" "-t" ];
              path = self.deployPkgs.${system}.deploy-rs.lib.activate.nixos value;
            };
          })
        self.nixosConfigurations;

      homeModules = mapModules ./modules/home import;

      overlay = self.overlays.default;

      overlays = {
        default = (final: prev: rec {
          kyaru = mapPackages final;
          master = mkPkgs inputs.nixpkgs-master final.hostPlatform.system;
          slirp4netns = prev.slirp4netns.overrideAttrs (oldAttrs: {
            patches = (oldAttrs.patches or [ ]) ++ [
              ./packages/slirp4netns.patch
            ];
          });
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (
              python-final: python-prev:
                {
                  bindep = python-final.callPackage ./packages/python3/bindep { };
                  ansible-builder = python-final.callPackage ./packages/python3/ansible-builder { };
                }
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
        packages = mapPackages pkgs;
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
      "https://usc1.contabostorage.com/43f37228fc484988a5809f4bc0e3ca6e:nix-cache"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "kyaru-nix-cache-1:Zu6gS5WZt4Kyvi95kCmlKlSyk+fbIwvuuEjBmC929KM="
    ];
  };
}
