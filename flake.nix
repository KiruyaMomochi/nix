{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";

    # Fixes for vscode server under NixOS
    # This is a fork of msteen/nixos-vscode-server which makes server location configurable
    vscode-server.url = "github:viperML/nixos-vscode-server/custom-path";

    # Windows subsystem for Linux support
    nixos-wsl.url = "github:nix-community/NixOS-WSL?ref=22.05-5c211b47";
  };

  outputs = { nixpkgs, home-manager, flake-utils, vscode-server, nixos-wsl, ... }:
    {
      nixosConfigurations = {
        # Desktop at lab
        gourmet = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/gourmet
          ];
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
        homeConfigurations = {
          kyaru = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              vscode-server.nixosModules.home
              ./home.nix
            ];
          };
        };
      }
    );
}
