{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    sops-nix = {
      url = "github:Mic92/sops-nix";
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
    oluceps = {
      url = "github:oluceps/nur-pkgs";
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
    in
    {
      lib = lib-kyaru;

      nixosConfigurations = mapHosts ./hosts { };

      # https://github.com/nix-community/home-manager/pull/3969
      homeConfigurations.kyaru = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = mkPkgs nixpkgs "x86_64-linux";
        extraSpecialArgs = { inherit inputs lib-kyaru; };
        modules = [ ./home.nix ];
      };

      nixosModules = mapModules ./modules import;
      homeModules = mapModules ./modules/home import;

      overlay = final: prev: rec {
        kyaru = mapPackages final;
        oluceps = inputs.oluceps.packages.${final.hostPlatform.system};
        master = mkPkgs inputs.nixpkgs-master final.hostPlatform.system;
        influxdb2-cli = master.influxdb2-cli;
        influxdb2-server = master.influxdb2-server;
        influxdb2-token-manipulator = master.influxdb2-token-manipulator;
      };

      templates = import ./templates;
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = mkPkgs nixpkgs system;
      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            inputs.agenix.packages.${system}.default
            self.packages.${system}.sops
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
