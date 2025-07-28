{ self, super, root, flake, ... }: { inputs, ... }: 
let
  inherit (flake.lib.home) makeOverridableHomeManagerConfig mkHome;
  inherit (flake.lib.packages) mkPkgs;
in
{
  flake = {
    # https://github.com/nix-community/home-manager/pull/3969
    homeConfigurations = rec {
        kyaru = kyaru-headless;
        kyaru-headless = mkHome { };
        kyaru-desktop = kyaru-headless.override (oldConfig: {
          modules = oldConfig.modules ++ [{
            programs.kyaru = {
              desktop.enable = true;
              kde.enable = true;
            };
          }];
        });
        "kyaru@lucent-academy" = mkHome { system = "aarch64-linux"; };
      };
  };
}
