{ config, lib, inputs, ... }:
let
  mkNoCuda = system: inputs.self.lib.packages.mkPkgsNoCuda inputs.nixpkgs system;
in
{
  config = lib.mkIf (config.nixpkgs.config.cudaSupport or false) {
    nixpkgs.overlays = [
      (final: prev:
        let
          pkgsNoCuda = mkNoCuda prev.stdenv.hostPlatform.system;
        in
        {
          inherit (pkgsNoCuda) firefox open-webui;
        }
      )
    ];
  };
}
