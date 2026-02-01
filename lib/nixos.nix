{ self, inputs, lib, ... }:
let
  inherit (lib.modules) mkDefault;
in
{
  patchNixpkgs = system: patches:
    let
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
    in
    if builtins.length patches == 0 then patchedNixpkgs else patchedNixpkgs;

  patchNixosSystem = system: patches:
    let
      patchedNixpkgs = self.patchNixpkgs system patches;
      patchedEvalConfig = import (patchedNixpkgs + "/nixos/lib/eval-config.nix");
      mkModulesConfig = customConfig: [
        (
          { config
          , pkgs
          , lib
          , ...
          }:
          {
            config = customConfig config;
          }
        )
      ];
      originalNixosSystem = args: lib.nixosSystem ({
        modules = args.modules ++ (mkModulesConfig (config: {
          # from https://nixos-and-flakes.thiscute.world/best-practices/nix-path-and-flake-registry
          # make `nix run nixpkgs#nixpkgs` use the same nixpkgs as the one used by this flake.
          # nixpkgs.flake.source is set automatically when generating with nixpkgs.lib.nixosSystem
          nix.registry.nixpkgs.flake = mkDefault inputs.nixpkgs;
          nixpkgs.config = import ../nixpkgs-config.nix;
        }));
      } // builtins.removeAttrs args [ "modules" ]);
      patchedNixosSystem = args: patchedEvalConfig ({
        # https://github.com/NixOS/nixpkgs/blob/35bfba9eefcaa9b167453e3c96105b9044d35df9/flake.nix#L64
        system = null;
        modules = args.modules ++ (mkModulesConfig (config: {
          nixpkgs.flake.source = mkDefault patchedNixpkgs;
          nixpkgs.pkgs = mkDefault (import config.nixpkgs.flake.source {
            system = config.nixpkgs.localSystem.system;
            config = import ../nixpkgs-config.nix;
          });
        }));
      } // builtins.removeAttrs args [ "modules" ]);
    in
    if builtins.length patches == 0 then originalNixosSystem else patchedNixosSystem;

  mkHost = system: hostname: config:
    self.patchNixosSystem system (import ../patches.nix) {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        {
          nixpkgs.overlays = [ inputs.self.overlays.default ];
          networking.hostName = mkDefault hostname;
        }
        ../nixosModules/kyaru/default.nix
        config
      ];
    };

  # Common logic for loading hosts from nixosConfigurations directory
  loadHosts = src:
    let
      loader = inputs.haumea.lib.loaders.verbatim;
      matcher = { inherit loader; matches = filename: filename == "default.nix"; };
      transformer = cursor: module:
        let
          depth = builtins.length cursor;
        in
        if depth == 0 then module
        else if depth == 1 then (module.default or null)
        else null;
    in
    inputs.haumea.lib.load {
      inherit src;
      loader = [ matcher ];
      transformer = [ transformer ];
    };

  systemOverride = hostname: {
    "lucent-academy" = "aarch64-linux";
  }.${hostname} or "x86_64-linux";
}
