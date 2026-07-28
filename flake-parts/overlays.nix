{
  self,
  super,
  root,
  flake,
  ...
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
        d2 = prev.d2.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ../packages/d2-ascii-cjk-scale.patch
          ];
        });
        # nu_plugin_polars 0.114.1 pins ethnum 1.5.2, whose mem::transmute(()) ->
        # TryFromIntError no longer compiles under rustc 1.97 (E0512). Carry the
        # lockfile bump to ethnum 1.5.3 from nixpkgs PR #546343; drop this once
        # that PR (or a nushell release containing the bump) lands.
        nushellPlugins = prev.nushellPlugins // {
          # Patch the lockfile in src rather than via cargoPatches: overrideAttrs
          # runs after buildRustPackage has already derived cargoDeps from the
          # original Cargo.lock, so a late cargoPatches never reaches the vendor
          # step. Handing over an already-patched src keeps that derivation
          # internal and only cargoHash has to be refreshed.
          polars = prev.nushellPlugins.polars.overrideAttrs (finalAttrs: old: {
            src = final.applyPatches {
              inherit (old) src;
              name = "${old.pname}-${old.version}-patched-src";
              patches = [ ../packages/nushell-plugin-polars-ethnum-1.5.3.patch ];
            };
            # cargoHash is read by buildRustPackage from its outer args before
            # mkDerivation is called, so overrideAttrs can't reach it. Override
            # cargoDeps directly, pointing at the already-patched finalAttrs.src
            # so fetchCargoVendor sees the updated Cargo.lock without extra patches.
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit (finalAttrs) pname version src;
              hash = "sha256-Cpv58bqpx1o0Dz2AykqzFY+PQE/Updr5MusQflpEF74=";
            };
          });
        };
        # krdp: nixpkgs missing plasma-wayland-protocols → WITH_PLASMA_SESSION not built
        # --plasma flag is a no-op without this, falls back to broken PortalSession
        # upstream CMakeLists: find_package(PlasmaWaylandProtocols REQUIRED) when BUILD_PLASMA_SESSION=ON
        kdePackages = prev.kdePackages.overrideScope (
          kfinal: kprev: {
            krdp = kprev.krdp.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [
                kfinal.plasma-wayland-protocols
              ];
            });
          }
        );
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
