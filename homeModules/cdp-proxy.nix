{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.services.cdp-proxy;

  cdpProxyScript = pkgs.writers.writePython3Bin "cdp-proxy"
    {
      libraries = [ pkgs.python3Packages.aiohttp ];
      flakeIgnore = [ "E501" "W503" ];
    }
    (builtins.readFile ./cdp-proxy.py);

  cdpCtlScript = pkgs.writers.writePython3Bin "cdp-ctl"
    {
      libraries = [ pkgs.python3Packages.aiohttp ];
      flakeIgnore = [ "E501" "W503" ];
    }
    (builtins.replaceStrings
      [ "http://127.0.0.1:9224" ]
      [ "http://127.0.0.1:${toString cfg.listenPort}" ]
      (builtins.readFile ./cdp-ctl.py));
in
{
  options.services.cdp-proxy = with lib; {
    enable = mkEnableOption "CDP Fallback Proxy (ordered upstreams + local headless)";

    listenPort = mkOption {
      type = types.port;
      default = 9224;
      description = "Port the CDP proxy listens on.";
    };

    upstreams = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Ordered list of CDP upstream URLs to probe. First reachable wins.";
      example = [
        "http://100.82.238.137:9222"
        "http://127.0.0.1:9223"
      ];
    };

    localCdpPort = mkOption {
      type = types.port;
      default = 9222;
      description = "Port for the local headless browser (last-resort fallback).";
    };

    localCdpHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Host the proxy uses to reach the local headless browser.

        Chrome 151+ respects --remote-debugging-address and binds the specified
        address (127.0.0.1 for IPv4, [::1] for IPv6). Earlier versions (≤150)
        ignored the flag and always bound IPv6 [::1].
      '';
    };

    browserPackage = mkOption {
      type = types.package;
      default = pkgs.google-chrome;
      description = "Browser package to use for headless mode.";
    };

    browserFlags = mkOption {
      type = types.listOf types.str;
      default = [
        "--headless"
        "--no-sandbox"
        "--disable-gpu"
        "--disable-software-rasterizer"
        "--disable-dev-shm-usage"
      ];
      description = "Extra flags for the headless browser.";
    };

    proxyServer = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Proxy server for the headless browser (e.g. http://127.0.0.1:3090).";
      example = "http://127.0.0.1:3090";
    };

    probeTimeout = mkOption {
      type = types.float;
      default = 1.5;
      description = "Seconds to wait when probing each upstream.";
    };

    localFallback = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Fall back to the local headless browser when no upstream answers, and start it with the
        session. When false, headless-browser is only defined (start it by hand) and the proxy
        answers 502 instead.
      '';
    };

    wakeCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command run when no upstream answers, before giving up or falling back; the proxy then waits for an upstream to come up.";
      example = "systemctl --user start my-chrome.service";
    };

    janitor = {
      upstream = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Upstream whose pages get closed once nobody has used them for idleSeconds. Only this browser is touched.";
        example = "http://127.0.0.1:9223";
      };

      idleSeconds = mkOption {
        type = types.int;
        default = 1800;
        description = "How long a page may sit unused before the janitor closes it. The last page is always kept.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # The control plane is intentionally unauthenticated and loopback-only.
    # cdp-ctl is installed with the same configured port as the service.
    home.packages = [ cdpCtlScript ];

    # Headless browser service
    systemd.user.services.headless-browser = {
      Unit = {
        Description = "Headless Chrome for CDP";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Install = {
        WantedBy = lib.optional cfg.localFallback "default.target";
      };

      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " ([
          "${cfg.browserPackage}/bin/${cfg.browserPackage.meta.mainProgram or "google-chrome-stable"}"
        ] ++ cfg.browserFlags ++ [
          "--remote-debugging-port=${toString cfg.localCdpPort}"
          "--remote-debugging-address=127.0.0.1"
        ] ++ lib.optional (cfg.proxyServer != null) "--proxy-server=${cfg.proxyServer}");
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # CDP fallback proxy service
    systemd.user.services.cdp-proxy = {
      Unit = {
        Description = "CDP Fallback Proxy (ordered upstreams)";
        After = lib.optional cfg.localFallback "headless-browser.service" ++ [ "network-online.target" ];
        Wants = lib.optional cfg.localFallback "headless-browser.service" ++ [ "network-online.target" ];
      };

      Install = {
        WantedBy = [ "default.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " ([
          "${cdpProxyScript}/bin/cdp-proxy"
          "--port" (toString cfg.listenPort)
        ] ++ lib.concatMap (u: [ "--upstream" u ]) cfg.upstreams ++ [
          "--local" (if cfg.localFallback then "http://${cfg.localCdpHost}:${toString cfg.localCdpPort}" else "''")
          "--probe-timeout" (toString cfg.probeTimeout)
        ] ++ lib.optionals (cfg.wakeCommand != null) [
          "--wake-command" (lib.escapeShellArg cfg.wakeCommand)
        ] ++ lib.optionals (cfg.janitor.upstream != null) [
          "--janitor-upstream" cfg.janitor.upstream
          "--janitor-idle" (toString cfg.janitor.idleSeconds)
        ]);
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
