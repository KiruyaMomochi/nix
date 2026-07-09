{
  buildGoModule,
  lib,
  nodejs,
  zip,
  mage,
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  yarnInstallHook,
}:
buildGoModule (
  finalAttrs:
  let
    frontend = stdenv.mkDerivation (frontendFinalAttrs: {
      inherit (finalAttrs) version src;
      pname = "${finalAttrs.pname}-frontend";

      yarnOfflineCache = fetchYarnDeps {
        yarnLock = frontendFinalAttrs.src + "/yarn.lock";
        hash = "sha256-xPSkVG1OnMFYvdkWWntFSI4ONKQwbu5XL0GVWsIgjVw=";
      };

      nativeBuildInputs = [
        yarnConfigHook
        yarnBuildHook
        yarnInstallHook
        # Needed for executing package.json scripts
        nodejs
      ];

      doCheck = true;

      installPhase = ''
        cp -r dist/ $out
      '';
    });
  in
  {
    pname = "info8fcc-greptimedb-datasource";
    version = "2.1.7";
    src = fetchFromGitHub {
      owner = "GreptimeTeam";
      repo = "greptimedb-grafana-datasource";
      rev = "v${finalAttrs.version}";
      hash = "sha256-oDzFCxd8obeAadGSG3dVB9F0y0Ud4oQgen5Ulq+29E8=";
    };
    nativeBuildInputs = [
      mage
    ];

    inherit frontend;
    vendorHash = "sha256-9CyW9yKRuI7lilYg+ghBi7+Fx5oISWMWZAlHNg0XJIE=";

    # Backend (Go) reads jsonData.host as bare hostname + separate port,
    # but the frontend proxy route and config UI treat it as a full URL.
    # Alert evaluation goes through the backend -> "invalid port" with our
    # provisioned host = http://127.0.0.1:4000. Patch: URL-split in LoadSettings.
    patches = [ ./url-host-backend.patch ];

    prePatch = ''
      cp -r ${frontend} dist
      chmod 0755 dist
    '';

    checkPhase = ''
      runHook preCheck

      mage test

      runHook postCheck
    '';

    buildPhase = ''
      runHook preBuild

      # Fixes "mkdir /homeless-shelter: permission denied" - "Error: error compiling magefiles" during build
      export HOME=$(mktemp -d)
      # TODO: mage -v build:linuxARM64
      mage build:linux

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # services.grafana.declarativePlugins symlinks $out directly into the
      # plugins dir, so $out must be the unpacked plugin directory (a zip like
      # upstream's release artifact would fail to load: "plugin not registered").
      cp -r dist $out

      runHook postInstall
    '';
  }
)
