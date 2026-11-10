{ self, inputs, ... }:
let
  inherit (self.lib.packages) mkPackages;
in
{
  perSystem = { system, pkgs, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = self.lib.packages.defaultOverlays;
      config = import ../nixpkgs-config.nix;
    };
    packages = (mkPackages pkgs) // {
      hermes-agent = pkgs.callPackage ../packages/hermes-agent { inherit inputs; };
    };
  };
}
