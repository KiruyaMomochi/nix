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
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/op/openobserve/package.nix
      openobserve = prev.openobserve.overrideAttrs (finalAttrs: oldAttrs: {
        version = "0.40.0";
        src = final.fetchFromGitHub {
          owner = "openobserve";
          repo = "openobserve";
          tag = "v${finalAttrs.version}";
          hash = "sha256-eiF9t3l6RcbO6d79iSuA7ikH2atizyNjWABQ9KAkkfE=";
        };
        preBuild =
          let
            web = final.buildNpmPackage rec {
              inherit (finalAttrs) src version;
              pname = "openobserve-ui";
              sourceRoot = "${src.name}/web";
              npmDepsHash = "sha256-ED3plf8Miw5+cbCOo+R1rbRxBju/MZvR0U9JA+NLr2k=";

              preBuild = ''
                # Patch vite config to not open the browser to visualize plugin composition
                substituteInPlace vite.config.ts \
                  --replace "open: true" "open: false";
              '';

              env = {
                NODE_OPTIONS = "--max-old-space-size=8192";
                # cypress tries to download binaries otherwise
                CYPRESS_INSTALL_BINARY = 0;
              };

              installPhase = ''
                runHook preInstall
                mkdir -p $out/share
                mv dist $out/share/openobserve-ui
                runHook postInstall
              '';
            };
          in
          ''
            cp -r ${web}/share/openobserve-ui web/dist
          '';
        # https://discourse.nixos.org/t/is-it-possible-to-override-cargosha256-in-buildrustpackage/4393/24
        cargoDeps = oldAttrs.cargoDeps.overrideAttrs (previousAttrs: {
          vendorStaging = previousAttrs.vendorStaging.overrideAttrs {
            inherit (finalAttrs) src;
            outputHash = "sha256-RNrI5DB5FTSLxeT7a62KkEnqyDYV4dQ3G65PPofa9Zs=";
          };
        });
        env = (oldAttrs.env or { }) // {
          SWAGGER_UI_DOWNLOAD_URL =
            # When updating:
            # - Look for the version of `utoipa-swagger-ui` at:
            #   https://github.com/StractOrg/stract/blob/<STRACT-REV>/Cargo.toml#L183
            # - Look at the corresponding version of `swagger-ui` at:
            #   https://github.com/juhaku/utoipa/blob/utoipa-swagger-ui-<UTOPIA-SWAGGER-UI-VERSION>/utoipa-swagger-ui/build.rs#L21-L22
            let
              swaggerUiVersion = "5.17.14";
              swaggerUi = final.fetchurl {
                url = "https://github.com/swagger-api/swagger-ui/archive/refs/tags/v${swaggerUiVersion}.zip";
                hash = "sha256-SBJE0IEgl7Efuu73n3HZQrFxYX+cn5UU5jrL4T5xzNw=";
              };
            in
            "file://${swaggerUi}";
        };

        # swagger-ui will once more be copied in the target directory during the check phase
        # Not deleting the existing unpacked archive leads to a `PermissionDenied` error
        preCheck = (oldAttrs.preCheck or "") + ''
          rm -rf target/${final.stdenv.hostPlatform.rust.cargoShortTarget}/release/build/
        '';
        checkFlags = (oldAttrs.checkFlags or [ ]) ++ [
          "--skip=service::github"
        #   "--skip=cli::data::tests::test_export_operator"
        #   "--skip=handler::http::request::search::saved_view::tests::test_create_view_post"
        #   "--skip=service::db::compact::downsampling::tests::test_downsampling"
        #   "--skip=service::db::compact::file_list::tests::test_file_list_offset"
        #   "--skip=service::db::compact::file_list::tests::test_file_list_process_offset"
        #   "--skip=service::db::compact::files::tests::test_compact_files"
        #   "--skip=service::db::user::tests::test_user"
        #   "--skip=service::metadata::trace_list_index::tests::test_write"
        ];
        patches = (oldAttrs.patches or [ ]) ++ [
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
