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
in
{
  options.services.cdp-proxy = with lib; {
    enable = mkEnableOption "CDP Fallback Proxy (headless Chrome + remote laptop)";

    listenPort = mkOption {
      type = types.port;
      default = 9224;
      description = "Port the CDP proxy listens on.";
    };

    laptopCdpUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:9222";
      description = "CDP endpoint of the remote laptop (e.g. via Tailscale).";
    };

    localCdpPort = mkOption {
      type = types.port;
      default = 9222;
      description = "Port for the local headless browser.";
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
      description = "Seconds to wait when probing the laptop CDP endpoint.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Headless browser service
    systemd.user.services.headless-browser = {
      Unit = {
        Description = "Headless Chrome for CDP";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Install = {
        WantedBy = [ "default.target" ];
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
        Description = "CDP Fallback Proxy (laptop -> local headless)";
        After = [ "headless-browser.service" "network-online.target" ];
        Wants = [ "headless-browser.service" "network-online.target" ];
      };

      Install = {
        WantedBy = [ "default.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " [
          "${cdpProxyScript}/bin/cdp-proxy"
          "--port" (toString cfg.listenPort)
          "--laptop" cfg.laptopCdpUrl
          "--local" "http://127.0.0.1:${toString cfg.localCdpPort}"
          "--probe-timeout" (toString cfg.probeTimeout)
        ];
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
