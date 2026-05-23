{ self
, super
, root
, flake
, ...
}:
{ inputs, ... }:
# TODO: support patching package with only .patch files?
let
  inherit (flake.lib.packages) mkPackages;
in
{
  flake = rec {
    overlay = overlays.default;
    overlays.default = (
      final: prev:
        let
          fenixOverlay = inputs.fenix.overlays.default;
          fenixApplied = fenixOverlay final prev;
        in
        {
          inherit (fenixApplied) fenix;
          kyaru = (mkPackages final) // {
            hermes-agent = final.callPackage ../packages/hermes-agent { inherit inputs; };
          };
          # nix = prev.nix.overrideAttrs (old: {
          #   buildInputs = (old.buildInputs or [ ]) ++ [ final.aws-sdk-cpp ];
          # });
          slirp4netns = prev.slirp4netns.overrideAttrs (oldAttrs: {
            patches = (oldAttrs.patches or [ ]) ++ [
              ../packages/slirp4netns.patch
            ];
          });
          singularity = prev.singularity.override ({
            nvidia-docker = final.libnvidia-container;
          });
          dragonflydb = prev.dragonflydb.override ({
            abseil-cpp = final.abseil-cpp_202505;
          });
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              open-interpreter = python-prev.open-interpreter.overridePythonAttrs (old: {
                pythonRelaxDeps = old.pythonRelaxDeps ++ [
                  "html2text"
                ];
              });
            })
          ];
        }
    );
  };
}
