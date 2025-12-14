{ self, super, root, flake, ... }: { inputs, withSystem, ... }: 
let
  inherit (flake.lib.home) makeOverridableHomeManagerConfig mkHome;
  inherit (flake.lib.packages) mkPkgs;
  pkgsOf = system: withSystem system ({ pkgs, ... }: pkgs);
in
{
  flake = {
    # https://github.com/nix-community/home-manager/pull/3969
    homeConfigurations = rec {
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
  };
}
