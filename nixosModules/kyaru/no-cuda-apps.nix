{ config, lib, inputs, ... }:
let
  mkNoCuda = system: inputs.self.lib.packages.mkPkgsNoCuda inputs.nixpkgs system;
in
{
  options.kyaru.enableNoCudaOverlay = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable overlay to replace heavy apps with non-CUDA versions";
  };

  config = lib.mkIf config.kyaru.enableNoCudaOverlay {
    nixpkgs.overlays = [
      (final: prev:
        let
          pkgsNoCuda = mkNoCuda final.stdenv.hostPlatform.system;
        in
        {
          inherit (pkgsNoCuda) firefox open-webui;
        }
      )
    ];
  };
}
