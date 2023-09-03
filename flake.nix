{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-agecrypt = {
      url = "github:vlaci/git-agecrypt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
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
    nixos-wsl.url = "github:nix-community/NixOS-WSL?ref=22.05-5c211b47";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    let
      inherit (lib.kyaru.nixos) mapHosts;
      inherit (lib.kyaru.packages) mapPackages;
      inherit (lib.attrsets) attrValues;

      mkPkgs = pkgs: system: import pkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };

      lib = nixpkgs.lib.extend (self: super: {
        kyaru = import ./lib { inherit inputs; lib = self; };
      });
    in
    {
      nixosConfigurations = mapHosts ./hosts { };

      homeConfigurations.kyaru = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = flake-utils.lib.system.x86_64-linux;
          allowUnfree = true;
        };
        modules = [
          {
            nixpkgs.overlays = attrValues self.overlays;
          }
          inputs.vscode-server.nixosModules.home
          ./home.nix
          ./modules/home/gui.nix
          ./modules/home/onedrive.nix
        ];
      };

      nixosModules.lmod = import ./modules/lmod;
      homeManagerModules = {
        ssh-fhs-fix = import ./modules/home/ssh-fhs-fix.nix;
        onedrive = import ./modules/home/onedrive.nix;
      };

      overlay = final: prev: {
        kyaru = mapPackages final;
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
        pkgs = mkPkgs nixpkgs system;
      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            inputs.agenix.packages.${system}.default
            inputs.git-agecrypt.packages.${system}.default
            sops
            age
            ssh-to-age
            ssh-to-pgp
            jq
            yq
            vscode-langservers-extracted
          ];
        };
        packages = mapPackages pkgs;
      }
    );
}
