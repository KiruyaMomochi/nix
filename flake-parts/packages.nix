{ self, super, root, flake, ... }: { inputs, ... }:
# TODO: support patching package with only .patch files?
let
  inherit (flake.lib.packages) mkPackages;
in
{
  perSystem = { system, pkgs, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.self.overlays.default ];
      config = import ../nixpkgs-config.nix;
    };
    packages = mkPackages pkgs;
  };
}
