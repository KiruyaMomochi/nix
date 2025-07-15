{ self, super, root, flake, ... }: { inputs, ... }:
# TODO: support patching package with only .patch files?
let
  inherit (flake.lib.packages) mkPackages;
in
{
  flake = rec {
    overlay = overlays.default;
    overlays.default = (final: prev: {
      kyaru = mkPackages final;
      slirp4netns = prev.slirp4netns.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ../packages/slirp4netns.patch
        ];
      });
      singularity = prev.singularity.override ({
        nvidia-docker = final.libnvidia-container;
      });
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (
          python-final: python-prev: {
            # Remove after https://github.com/NixOS/nixpkgs/pull/382920 is merged
            rapidocr-onnxruntime = python-prev.rapidocr-onnxruntime.overridePythonAttrs (old: {
              disabledTests = final.lib.throwIf (builtins.elem "test_ort_dml_warning" old.disabledTests) "test_ort_dml_warning is already in disabledTests, remove the patch!" (old.disabledTests ++ final.lib.optionals final.onnxruntime.cudaSupport [
                # segfault when built with cuda support but GPU is not availaible in build environment
                "test_ort_cuda_warning"
                "test_ort_dml_warning"
              ]);
            });
          }
        )
      ];
      aider-chat-with-help =
        final.python312Packages.toPythonApplication (
          (final.aider-chat.withOptional { withHelp = true; }).overridePythonAttrs (
            old: {
              disabledTests = (old.disabledTests or [ ]) ++ [ "test_cmd_tokens_output" ];
              disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
                # Tests require network access
                "tests/basic/test_repomap.py"
              ];
            }
          )
        );
    });
  };
}
