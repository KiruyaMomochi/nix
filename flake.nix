{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-master.url = "github:NixOS/nixpkgs";

    deploy-rs.url = "github:serokell/deploy-rs";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems = {
      url = "github:nix-systems/default";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    haumea = {
      url = "github:nix-community/haumea";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Fixes for vscode server under NixOS
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    # Windows subsystem for Linux support
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL?ref=22.05-5c211b47";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs@{ self, flake-parts, deploy-rs, systems, haumea, ... }:
    let
      # inherit (lib.kyaru.nixos) mapHosts;
      # inherit (lib.kyaru.packages) mapPackages;
      # inherit (lib.kyaru.modules) mapModules;
      inherit (nixpkgs.lib.attrsets) unionOfDisjoint;

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

      nixpkgs = originNixpkgs;
    in
    # top-level module definitiom
    flake-parts.lib.mkFlake
      {
        inherit inputs;
      }
      # module options
      ({ withSystem, flake-parts-lib, ... }: {
        systems = import systems;
        debug = true;

        imports =
          let
            modules = inputs.haumea.lib.load {
              src = ./src/flake-parts;
              loader = args: path: flake-parts-lib.importApply path args;
              inputs = {
                inherit withSystem;
                flake = self;
              };
            };
            liftedModules =
              if modules ? "perSystem" then
                (
                  unionOfDisjoint
                    (builtins.removeAttrs modules [ "perSystem" ])
                    (modules.perSystem)
                ) else modules;
          in
          builtins.attrValues liftedModules;
      });
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cuda-maintainers.cachix.org"
      "https://objects.kyaru.bond/nix-cache"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "kyaru-nix-cache-1:Zu6gS5WZt4Kyvi95kCmlKlSyk+fbIwvuuEjBmC929KM="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
}
