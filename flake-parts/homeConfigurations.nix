{ self, super, root, flake, ... }: { inputs, withSystem, ... }: 
let
  inherit (flake.lib.home) makeOverridableHomeManagerConfig mkHome loadHomes;
  inherit (flake.lib.packages) mkPkgs;
  pkgsOf = system: withSystem system ({ pkgs, ... }: pkgs);

  baseProfiles = rec {
    kyaru = kyaru-headless;
    kyaru-headless = mkHome { pkgs = pkgsOf "x86_64-linux"; };
    kyaru-desktop = kyaru-headless.override (oldConfig: {
      modules = oldConfig.modules ++ [{
        programs.kyaru = {
          desktop.enable = true;
          kde.enable = true;
        };
      }];
    });
    "kyaru@lucent-academy" = mkHome { pkgs = pkgsOf "aarch64-linux"; };
  };

  # Per-machine overrides from homeConfigurations/ directory
  machineModules = loadHomes ../homeConfigurations;

  # For each machine, create a homeConfiguration by overriding kyaru-headless
  # with the machine-specific module
  machineConfigs = builtins.mapAttrs (name: module:
    (mkHome { pkgs = pkgsOf "x86_64-linux"; }).override (oldConfig: {
      modules = oldConfig.modules ++ [ module ];
    })
  ) machineModules;
in
{
  flake = {
    # https://github.com/nix-community/home-manager/pull/3969
    homeConfigurations = baseProfiles // machineConfigs;
  };
}
