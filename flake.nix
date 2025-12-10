{
  description = "Nix configuration of Kiruya Momochi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-master.url = "github:NixOS/nixpkgs";

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
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = inputs@{ self, flake-parts, systems, haumea, ... }:
    let
      inherit (inputs.nixpkgs.lib.attrsets) unionOfDisjoint;
    in
    # top-level module definitiom
      # flake-parts docs: https://flake.parts/options/flake-parts.html
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
            # haumea docs: https://nix-community.github.io/haumea/intro/getting-started.html
            modules = inputs.haumea.lib.load {
              # each imported files have two arguments
              # refer to ./flake-parts/default.nix for example
              # first one is the `args` referenced int the `loader` line 
              # second one is the module argument, which is "all module options" and "special args"
              src = ./flake-parts;
              # importApply docs: https://flake.parts/define-module-in-separate-file.html#importapply
              # args are: { self, super, root, flake, withSystem }
              loader = args: path: flake-parts-lib.importApply path args;
              # additional args are defined here
              inputs = {
                inherit withSystem;
                flake = self;
              };
            };
            # lift flake-parts/per-system/*.nix to the root
            # this *only lift the directory layout*, does not touch the directory layout
            liftedModules =
              # perSystem is a flake-parts attribute
              # we want to bring them up
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
      "https://colmena.cachix.org"
      "https://objects.kyaru.bond/nix-cache"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "kyaru-nix-cache-1:Zu6gS5WZt4Kyvi95kCmlKlSyk+fbIwvuuEjBmC929KM="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "colmena.cachix.org-1:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
    ];
  };
}
