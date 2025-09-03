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
      openobserve = prev.openobserve.overrideAttrs (oldAttrs: {
        checkFlags = (oldAttrs.checkFlags or [ ]) ++ [
          "--skip=cli::data::tests::test_export_operator"
          "--skip=handler::http::request::search::saved_view::tests::test_create_view_post"
          "--skip=service::db::compact::downsampling::tests::test_downsampling"
          "--skip=service::db::compact::file_list::tests::test_file_list_offset"
          "--skip=service::db::compact::file_list::tests::test_file_list_process_offset"
          "--skip=service::db::compact::files::tests::test_compact_files"
          "--skip=service::db::user::tests::test_user"
          "--skip=service::metadata::trace_list_index::tests::test_write"
        ];
        patches = (oldAttrs.patches or [ ] ) ++ [
          ../packages/openobserve.patch
        ];
      });
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (
          python-final: python-prev: {
            open-interpreter = python-prev.open-interpreter.overridePythonAttrs (old: {
              pythonRelaxDeps = old.pythonRelaxDeps ++ [
                "html2text"
              ];
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
