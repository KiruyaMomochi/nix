{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.services.hermes-gateway;

  # The upstream nix/hermes-agent.nix installPhase omits locales/, causing
  # agent.i18n to fall back to bare key strings (e.g. "gateway.reset.header_default")
  # in Telegram messages.
  #
  # Root cause: agent/i18n.py uses Path(__file__).resolve().parent.parent / "locales".
  # In nix, .resolve() (and even os.path.join with "..") follows hardlinks in the
  # venv back to the *original* hermes-agent wheel derivation's site-packages/,
  # where locales/ doesn't exist.
  #
  # Fix: override the hermes-agent wheel derivation to add locales/ into its
  # site-packages/, then substitute it into hermesVenv's NIX_PYPROJECT_DEPS so
  # pyprojectMakeVenv hardlinks the patched wheel instead.  Since .resolve() / ".."
  # traversal both land in the wheel derivation, locales/ will be found there.
  # Patch gateway/run.py to convert OpenAI image_url parts to Anthropic
  # source format when api_mode=anthropic_messages.  The Anthropic SDK does
  # not auto-convert image_url → source, so native vision on custom Anthropic
  # endpoints (e.g. 4router) fails with HTTP 500 without this fix.
  #
  # Patch agent/chat_completion_helpers.py so runtime fallback preserves
  # api_mode/transport from fallback_providers entries or named custom_providers.
  # Without this, custom Anthropic-compatible providers used only as fallback
  # can be activated with api_mode=chat_completions and return empty responses.
  patchVisionAnthropicFormat = pkg:
    let
      sitePackages = pkgs.python312.sitePackages;
      origVenv = pkg.passthru.hermesVenv;
      origWheel = builtins.head (
        builtins.filter
          (drv: lib.hasPrefix "/nix/store" drv && lib.hasSuffix "hermes-agent-0.14.0" drv)
          (lib.splitString ":" origVenv.NIX_PYPROJECT_DEPS)
      );
      patchedWheel = (pkgs.callPackage ({ stdenv, patch }: stdenv.mkDerivation {
        name = "hermes-agent-0.14.0";
        src = origWheel;
        dontUnpack = true;
        nativeBuildInputs = [ patch ];
        installPhase = ''
          cp -a $src $out
          chmod -R u+w $out
          patch -p1 -d $out/${sitePackages} < ${./hermes-vision-anthropic.patch}
          patch -p1 -d $out/${sitePackages} < ${./hermes-fallback-custom-api-mode.patch}
        '';
      }) {});
      patchedVenv = origVenv.overrideAttrs (old: {
        NIX_PYPROJECT_DEPS = builtins.replaceStrings
          [ origWheel ]
          [ "${patchedWheel}" ]
          old.NIX_PYPROJECT_DEPS;
      });
    in
    pkg.overrideAttrs (old: {
      installPhase = builtins.replaceStrings
        [ (builtins.unsafeDiscardStringContext "${origVenv}") ]
        [ "${patchedVenv}" ]
        old.installPhase;
      postInstall = (old.postInstall or "") + ''
        for wrapper in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
          if grep -q ${origVenv} "$wrapper"; then
            substituteInPlace "$wrapper" --replace-fail ${origVenv} ${patchedVenv}
          fi
        done
      '';
      passthru = old.passthru // { hermesVenv = patchedVenv; };
    });

  patchLocales = pkg:
    let
      localesSrc = lib.cleanSource (inputs.hermes-agent + "/locales");
      sitePackages = pkgs.python312.sitePackages;

      origVenv = pkg.passthru.hermesVenv;

      # The hermes-agent wheel derivation is the first entry in NIX_PYPROJECT_DEPS.
      # We override it to add locales/ into its site-packages/.
      origWheel = builtins.head (
        builtins.filter
          (drv: lib.hasPrefix "/nix/store" drv && lib.hasSuffix "hermes-agent-0.14.0" drv)
          (lib.splitString ":" origVenv.NIX_PYPROJECT_DEPS)
      );

      patchedWheel = (pkgs.callPackage ({ stdenv }: stdenv.mkDerivation {
        name = "hermes-agent-0.14.0";
        # Just copy origWheel and add locales
        src = origWheel;
        dontUnpack = true;
        installPhase = ''
          cp -a $src $out
          chmod -R u+w $out
          cp -r ${localesSrc} $out/${sitePackages}/locales
        '';
      }) {});

      patchedVenv = origVenv.overrideAttrs (old: {
        NIX_PYPROJECT_DEPS = builtins.replaceStrings
          [ origWheel ]
          [ "${patchedWheel}" ]
          old.NIX_PYPROJECT_DEPS;
      });
    in
    pkg.overrideAttrs (old: {
      installPhase = builtins.replaceStrings
        [ (builtins.unsafeDiscardStringContext "${origVenv}") ]
        [ "${patchedVenv}" ]
        old.installPhase;
      postInstall = (old.postInstall or "") + ''
        for wrapper in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
          if grep -q ${origVenv} "$wrapper"; then
            substituteInPlace "$wrapper" --replace-fail ${origVenv} ${patchedVenv}
          fi
        done
      '';
      passthru = old.passthru // { hermesVenv = patchedVenv; };
    });

  effectivePackage =
    let
      base =
        if cfg.extraDependencyGroups == []
        then cfg.package
        else cfg.package.override { extraDependencyGroups = cfg.extraDependencyGroups; };
    in
    patchLocales (patchVisionAnthropicFormat base);
in
{
  options.services.hermes-gateway = with lib; {
    enable = mkEnableOption "Hermes Agent Gateway service";

    package = mkOption {
      type = types.package;
      description = "The hermes-agent package to use.";
    };

    extraDependencyGroups = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Additional pyproject.toml optional-dependency groups to include.
        Use this for lazy-installed extras that fail in read-only Nix envs
        (e.g. "anthropic", "exa", "telegram").
      '';
    };

    hermesHome = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.hermes";
      description = "Path to HERMES_HOME directory.";
    };

    workingDirectory = mkOption {
      type = types.str;
      default = config.home.homeDirectory;
      description = "Working directory for the gateway process.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = "${cfg.hermesHome}/.env";
      description = "Path to environment file with secrets (API keys etc).";
    };

    extraPaths = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra directories to prepend to PATH in the service.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Make hermes CLI available in interactive shells, with HERMES_HOME defaulting
    # to cfg.hermesHome so the CLI and gateway service stay in sync without
    # requiring the user to set a session variable.  --set-default is used so an
    # explicit HERMES_HOME= in the environment still takes precedence.
    home.packages = [
      (effectivePackage.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          for wrapper in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
            wrapProgram "$wrapper" --set-default HERMES_HOME ${lib.escapeShellArg cfg.hermesHome}
          done
        '';
      }))
    ];

    systemd.user.services.hermes-gateway = {
      Unit = {
        Description = "Hermes Agent Gateway - Messaging Platform Integration";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        StartLimitIntervalSec = 0;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${effectivePackage}/bin/hermes gateway run";
        WorkingDirectory = cfg.workingDirectory;

        Environment = [
          "PATH=${lib.concatStringsSep ":" (cfg.extraPaths ++ ["${pkgs.bash}/bin" "${effectivePackage}/bin" "/run/current-system/sw/bin"])}"
          "HERMES_HOME=${cfg.hermesHome}"
        ];

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;

        Restart = "always";
        RestartSec = 5;
        RestartMaxDelaySec = 300;
        RestartSteps = 5;
        RestartForceExitStatus = 75;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        ExecReload = "${pkgs.util-linux}/bin/kill -USR1 $MAINPID";
        TimeoutStopSec = 210;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
