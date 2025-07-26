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
