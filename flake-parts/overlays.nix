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
        version = "0.50.2";
        src = final.fetchFromGitHub {
          owner = "openobserve";
          repo = "openobserve";
          tag = "v${finalAttrs.version}";
          hash = "sha256-e5xEbzGJrZ96LBEdiGVTNX5j62HqX2dwQvfA9WUdxKE=";
        };
        preBuild =
          let
            web = final.buildNpmPackage rec {
              inherit (finalAttrs) src version;
              pname = "openobserve-ui";
              sourceRoot = "${src.name}/web";
              npmDepsHash = "sha256-UNdFqUJI/pdHJjjA5Aebnvq1T7oITJ1R96rEQOBxTug=";

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
            outputHash = "sha256-d67ZeAth0Q8h8xXJZl+2Z2/+M54Ef4xFlsPT9CnrwK4=";
          };
        });
        checkFlags = (oldAttrs.checkFlags or [ ]) ++ [
          "--skip=service::db::enrichment_table::get_enrichment_data_from_db"
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
    });
  };
}
