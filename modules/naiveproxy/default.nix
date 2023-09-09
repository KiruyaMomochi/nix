{ config, lib, pkgs, utils, ... }:
with lib;
let
  cfg = config.services.naiveproxy;
  settingsFormat = pkgs.formats.json { };
  secretOptions = {
    options = {
      _secret = mkOption {
        type = types.str;
        description = ''
          Path to a file containing a secret value.
        '';
      };
    };
  };
in
{
  options.services.naiveproxy = {
    enable = mkEnableOption "NaiveProxy";
    package = mkPackageOption pkgs [ "kyaru" "naiveproxy" ] { };

    settings = mkOption {
      type = types.submodule {
        freeformType = settingsFormat.type;

        options = {
          listen = mkOption {
            type = with types; oneOf [ nonEmptyStr (listOf nonEmptyStr) ];
            example = "socks://127.0.0.1:1080";
            description = ''
              Listens at addr:port with protocol <proto>.
              Can be specified multiple times to listen on multiple ports.

              Available proto: socks, http, redir.
              Default proto, addr, port: socks, 0.0.0.0, 1080.

              * http: Supports only proxying https:// URLs, no http://.

              * redir: Works with certain iptables setup.

                (Redirecting locally originated traffic)
                iptables -t nat -A OUTPUT -d $proxy_server_ip -j RETURN
                iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports 1080

                (Redirecting forwarded traffic on a router)
                iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 1080

                Also activates a DNS resolver on the same UDP port. Similar iptables
                rules can redirect DNS queries to this resolver. The resolver returns
                artificial addresses that are translated back to the original domain
                names in proxy requests and then resolved remotely.

                The artificial results are not saved for privacy, so restarting the
                resolver may cause downstream to cache stale results.
            '';
          };

          proxy = mkOption {
            type = with types; oneOf [ nonEmptyStr (submodule secretOptions) ];
            example = "https://user:pass@domain.example";
            description = ''
              Routes traffic via the proxy server. Connects directly by default.
              Available proto: https, quic. Infers port by default.
            '';
          };

          log = mkOption {
            type = types.nullOr types.path;
            example = "/var/log/naiveproxy.log";
            default = null;
            description = ''
              Saves log to the file at <path>. If path is empty, prints to
              console. No log is saved or printed by default for privacy.
            '';
          };
        };
      };
      default = { };
      description = ''
        Settings for NaïveProxy. see
        <link xlink:href="https://github.com/klzgrad/naiveproxy/blob/master/USAGE.txt">
        for supported values.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.etc."naiveproxy/config.json" = {
      mode = "0400";
      source = settingsFormat.generate "naiveproxy-config.json" cfg.settings;
    };

    systemd.services.naiveproxy =
      let
        configPath = "/var/lib/naiveproxy/config.json";
      in
      {
        restartTriggers = [ configPath ];
        restartIfChanged = true;
        description = "NaïveProxy service";
        wantedBy = [ "multi-user.target" ];
        preStart = ''
          umask u=rw,g=,o=
          ${utils.genJqSecretsReplacementSnippet cfg.settings configPath}
        '';
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${cfg.package}/bin/naiveproxy ${configPath}";
          PrivateTmp = true;
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          StateDirectory = "naiveproxy";
          Restart = "on-failure";
        };
      };
  };
}
