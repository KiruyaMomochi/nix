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
    version = "3.0.3";
    src = fetchFromGitHub {
      owner = "GreptimeTeam";
      repo = "greptimedb-grafana-datasource";
      rev = "v${finalAttrs.version}";
      hash = "sha256-OoiGx5ofqIzclXPa3fX5xGDlLCfHBIjEbfnk47qNIiI=";
    };
    nativeBuildInputs = [
      mage
    ];

    inherit frontend;
    vendorHash = "sha256-XiKGij3higC9VNeD0G3yABDh2kbYnIJibPcSIfBHZsc=";

    # No local patches. Up to 2.x the Go backend required a bare hostname plus
    # a separate port, so a provisioned host of http://127.0.0.1:4000 (the form
    # the frontend proxy route needs) made alert evaluation fail with
    # "invalid port"; url-host-backend.patch split the URL in LoadSettings.
    # 3.0.0 made the backend URL-aware upstream: isValid() accepts an http(s)://
    # host without a port, SQLURL() passes it through, and getTLSConfig() infers
    # TLS from the scheme. Keeping the patch would break that, and upstream's
    # own tests now assert Host stays a full URL.

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
