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
  # In nix, .resolve() follows hardlinks back to the *original* hermes-agent wheel
  # derivation's site-packages/, where locales/ doesn't exist.  The venv's
  # site-packages/ has its own copy but .resolve() bypasses it.
  #
  # Fix: copy locales/ into the venv's site-packages/, then install a .pth file
  # that monkey-patches agent.i18n._locales_dir() at Python startup to point at
  # the venv-local copy instead of following .resolve() into the sealed wheel drv.
  # .pth files starting with "import" are exec'd by site.py on every interpreter
  # start, so this works for both `hermes gateway run` and manual `hermes` CLI.
  patchLocales = pkg:
    let
      localesSrc = lib.cleanSource (inputs.hermes-agent + "/locales");
      sitePackages = pkgs.python312.sitePackages;

      # .pth files starting with "import" are exec()'d by site.py at startup.
      # Monkey-patches _locales_dir to use the venv-local locales/ dir,
      # bypassing .resolve() which follows hardlinks into the sealed wheel drv.
      localesPth = pkgs.writeText "hermes-locales.pth"
        ''import importlib as _il, pathlib as _pl, os as _os; _m = _il.import_module("agent.i18n"); _m._locales_dir = lambda: _pl.Path(_os.path.join(_os.path.dirname(_os.path.abspath(_m.__file__)), "..", "locales"))'';

      patchedVenv = pkg.passthru.hermesVenv.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          cp -r ${localesSrc} $out/${sitePackages}/locales
          cp ${localesPth} $out/${sitePackages}/hermes-locales.pth
        '';
      });
    in
    pkg.overrideAttrs (old: {
      installPhase = builtins.replaceStrings
        [ (builtins.unsafeDiscardStringContext "${pkg.passthru.hermesVenv}") ]
        [ "${patchedVenv}" ]
        old.installPhase;
      passthru = old.passthru // { hermesVenv = patchedVenv; };
    });

  effectivePackage =
    let
      base =
        if cfg.extraDependencyGroups == []
        then cfg.package
        else cfg.package.override { extraDependencyGroups = cfg.extraDependencyGroups; };
    in
    patchLocales base;
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
    # Make hermes CLI available in interactive shells
    home.packages = [ effectivePackage ];

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

        # Prepend bash to PATH so hermes terminal tool can find it via
        # shutil.which("bash") -- otherwise nushell users get a broken terminal tool.
        # Also include extraPaths (e.g. ~/.local/bin for scripts the agent can call).
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
