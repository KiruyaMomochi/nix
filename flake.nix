{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
    # This is a fork of msteen/nixos-vscode-server which makes server location configurable
    vscode-server.url = "github:nix-community/nixos-vscode-server";

    # Windows subsystem for Linux support
    nixos-wsl.url = "github:nix-community/NixOS-WSL?ref=22.05-5c211b47";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, flake-utils, vscode-server, nixos-wsl, lanzaboote, agenix, ... }:
    {
      nixosConfigurations = {
        # Desktop at lion
        carmina = nixpkgs.lib.nixosSystem {
          system = flake-utils.lib.system.x86_64-linux;
          modules = [
            agenix.nixosModules.default
            ./hosts/carmina/configuration.nix
            lanzaboote.nixosModules.lanzaboote
            ({ pkgs, lib, ... }: {
              environment.systemPackages = [
                pkgs.sbctl
                pkgs.git
              ];

              # Lanzaboote currently replaces the systemd-boot module.
              # This setting is usually set to true in configuration.nix
              # generated at installation time. So we force it to false
              # for now.
              boot.loader.systemd-boot.enable = lib.mkForce false;

              boot.lanzaboote = {
                enable = true;
                pkiBundle = "/etc/secureboot";
              };
            })
          ];
        };

        caon = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules =
            [
              agenix.nixosModules.default
              ./hosts/caon/configuration.nix
              lanzaboote.nixosModules.lanzaboote
              ({ pkgs, lib, ... }: {
                environment.systemPackages = [
                  pkgs.sbctl
                  pkgs.git
                ];

                # Lanzaboote currently replaces the systemd-boot module.
                # This setting is usually set to true in configuration.nix
                # generated at installation time. So we force it to false
                # for now.
                boot.loader.systemd-boot.enable = lib.mkForce false;

                boot.lanzaboote = {
                  enable = true;
                  pkiBundle = "/etc/secureboot";
                };
              })
            ];
        };
      };

      homeConfigurations.kyaru = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = flake-utils.lib.system.x86_64-linux;
          allowUnfree = true;
        };
        modules = [
          ({ lib, ... }: {
            nixpkgs.overlays = lib.attrsets.attrValues self.overlays;
          })
          vscode-server.nixosModules.home
          ./home.nix
          ./modules/home/gui.nix
        ];
      };

      nixosModules.lmod = import ./modules/lmod;
      homeManagerModules = {
        ssh-fhs-fix = import ./modules/home/ssh-fhs-fix.nix;
        onedrive = import ./modules/home/onedrive.nix;
      };
      overlays = {
        lmod = final: prev: {
          lmod = final.callPackage ./packages/lmod { };
        };
        goldendict-ng = pkgs: prev: {
          goldendict-ng = pkgs.libsForQt5.callPackage ./packages/goldendict-ng { };
        };
      };

      templates = {
        pnpm = {
          path = ./templates/pnpm;
          description = "pnpm package manager";
        };
      };

    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          packages = [
            agenix.packages.${system}.default
          ];
        };

        packages = {
          lmod = pkgs.callPackage ./packages/lmod { };
          openxr-hpp = pkgs.callPackage ./packages/openxr-hpp { };
          goldendict-ng = pkgs.libsForQt5.callPackage ./packages/goldendict-ng { };
        };
      }
    );
}
