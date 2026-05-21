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
  # Fix: override hermesVenv (via overrideAttrs postInstall) to copy locales/
  # into site-packages/ while $out is still writable, then substitute the
  # patched venv into hermes-agent's installPhase via override so makeWrapper
  # picks up the right venv path.
  #
  # agent/i18n.py._locales_dir():
  #   Path(__file__).resolve().parent.parent / "locales"
  #   .resolve() follows nix symlinks back to the *original* derivation where
  #   locales/ doesn't exist.  We patch out .resolve() and copy locales/ into
  #   the venv's site-packages/ so the un-resolved path finds them.
  patchLocales = pkg:
    let
      locales = lib.cleanSource (inputs.hermes-agent + "/locales");
      sitePackages = pkgs.python312.sitePackages;
      # Build a new hermesVenv derivation that includes locales/
      patchedVenv = pkg.passthru.hermesVenv.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          cp -r ${locales} $out/${sitePackages}/locales

          # agent/i18n.py uses Path(__file__).resolve().parent.parent / "locales"
          # which follows nix symlinks back to the original (un-patched) derivation.
          # Drop the .resolve() so it stays within *this* venv where locales/ lives.
          # The file may be a symlink into the read-only original derivation, so
          # copy-then-replace to ensure we have a writable real file.
          local f=$out/${sitePackages}/agent/i18n.py
          cp --remove-destination "$(readlink -f "$f")" "$f"
          ${pkgs.gnused}/bin/sed -i 's/Path(__file__).resolve().parent.parent/Path(__file__).parent.parent/' "$f"
        '';
      });
    in
    # Substitute patchedVenv wherever the original hermesVenv store path appears
    # in the installPhase (makeWrapper calls, HERMES_PYTHON, collision check).
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
