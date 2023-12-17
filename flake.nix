{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
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
    nixos-wsl.url = "github:nix-community/NixOS-WSL?ref=22.05-5c211b47";
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
    in
    {
      lib = lib-kyaru;

      nixosConfigurations = mapHosts ./hosts { };

      # https://github.com/nix-community/home-manager/pull/3969
      homeConfigurations.kyaru =
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
        makeOverridableHomeManagerConfig {
          pkgs = mkPkgs nixpkgs "x86_64-linux";
          extraSpecialArgs = {
            inherit inputs lib-kyaru;
          };
          modules = [ ./home.nix ];
        };

      nixosModules = mapModules ./modules import;
      homeModules = mapModules ./modules/home import;

      overlay = final: prev: rec {
        kyaru = mapPackages final;
        master = mkPkgs inputs.nixpkgs-master final.hostPlatform.system;
        influxdb2-cli = master.influxdb2-cli;
        influxdb2-server = master.influxdb2-server;
        influxdb2-token-manipulator = master.influxdb2-token-manipulator;
        rclone = prev.rclone.override {
          buildGoModule = args: prev.buildGoModule (args // {
            arc = prev.fetchFromGitHub {
              owner = "rclone";
              repo = "rclone";
              rev = "c69eb84573c85206ab028eda2987180e049ef2e4";
              hash = "sha256-WVU/3lCfUBoIGoqxTI2nMS383XTdHFaToh7MQG9emgA=";
            };
            vendorHash = "sha256-eYIGVCTvUfGbsIMFthEfD0r6aeA7Ly9xJ8PJ6hR2SjA=";
          });
        };
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
