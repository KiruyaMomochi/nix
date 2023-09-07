# Fix SSH config from symbolic points to copy files
# https://github.com/nix-community/home-manager/issues/322

{ config
, lib
, pkgs
, ...
}:

with lib;

let

  cfg = config.programs.ssh;

  isPath = x: builtins.substring 0 1 (toString x) == "/";

  addressPort = entry:
    if isPath entry.address
    then " ${entry.address}"
    else " [${entry.address}]:${toString entry.port}";

  unwords = builtins.concatStringsSep " ";

  matchBlockStr = key: cf: concatStringsSep "\n" (
    let
      hostOrDagName = if cf.host != null then cf.host else key;
      matchHead =
        if cf.match != null
        then "Match ${cf.match}"
        else "Host ${hostOrDagName}";
    in
    [ "${matchHead}" ]
    ++ optional (cf.port != null) "  Port ${toString cf.port}"
    ++ optional (cf.forwardAgent != null) "  ForwardAgent ${lib.hm.booleans.yesNo cf.forwardAgent}"
    ++ optional cf.forwardX11 "  ForwardX11 yes"
    ++ optional cf.forwardX11Trusted "  ForwardX11Trusted yes"
    ++ optional cf.identitiesOnly "  IdentitiesOnly yes"
    ++ optional (cf.user != null) "  User ${cf.user}"
    ++ optional (cf.hostname != null) "  HostName ${cf.hostname}"
    ++ optional (cf.addressFamily != null) "  AddressFamily ${cf.addressFamily}"
    ++ optional (cf.sendEnv != [ ]) "  SendEnv ${unwords cf.sendEnv}"
    ++ optional (cf.serverAliveInterval != 0)
      "  ServerAliveInterval ${toString cf.serverAliveInterval}"
    ++ optional (cf.serverAliveCountMax != 3)
      "  ServerAliveCountMax ${toString cf.serverAliveCountMax}"
    ++ optional (cf.compression != null) "  Compression ${lib.hm.booleans.yesNo cf.compression}"
    ++ optional (!cf.checkHostIP) "  CheckHostIP no"
    ++ optional (cf.proxyCommand != null) "  ProxyCommand ${cf.proxyCommand}"
    ++ optional (cf.proxyJump != null) "  ProxyJump ${cf.proxyJump}"
    ++ map (file: "  IdentityFile ${file}") cf.identityFile
    ++ map (file: "  CertificateFile ${file}") cf.certificateFile
    ++ map (f: "  LocalForward" + addressPort f.bind + addressPort f.host) cf.localForwards
    ++ map (f: "  RemoteForward" + addressPort f.bind + addressPort f.host) cf.remoteForwards
    ++ map (f: "  DynamicForward" + addressPort f) cf.dynamicForwards
    ++ mapAttrsToList (n: v: "  ${n} ${v}") cf.extraOptions
  );

in

{
  options.programs.kyaru.ssh = {
    copy = mkEnableOption "Copy SSH config instead of symlinking it";
  };

  config = mkIf config.programs.kyaru.ssh.copy {
    assertions = [
      {
        assertion =
          let
            # `builtins.any`/`lib.lists.any` does not return `true` if there are no elements.
            any' = pred: items: if items == [ ] then true else any pred items;
            # Check that if `entry.address` is defined, and is a path, that `entry.port` has not
            # been defined.
            noPathWithPort = entry: entry.address != null && isPath entry.address -> entry.port == null;
            checkDynamic = block: any' noPathWithPort block.dynamicForwards;
            checkBindAndHost = fwd: noPathWithPort fwd.bind && noPathWithPort fwd.host;
            checkLocal = block: any' checkBindAndHost block.localForwards;
            checkRemote = block: any' checkBindAndHost block.remoteForwards;
            checkMatchBlock = block: all (fn: fn block) [ checkLocal checkRemote checkDynamic ];
          in
          any' checkMatchBlock (map (block: block.data) (builtins.attrValues cfg.matchBlocks));
        message = "Forwarded paths cannot have ports.";
      }
    ];

    home.activation.copySshConfig =
      let
        sortedMatchBlocks = hm.dag.topoSort cfg.matchBlocks;
        sortedMatchBlocksStr = builtins.toJSON sortedMatchBlocks;
        matchBlocks =
          if sortedMatchBlocks ? result
          then sortedMatchBlocks.result
          else abort "Dependency cycle in SSH match blocks: ${sortedMatchBlocksStr}";
        cfgFile = pkgs.writeText "ssh-config" ''
          # Generated by home-manager, YOUR EDIT MAY LOST!
          ${concatStringsSep "\n" (
            (mapAttrsToList (n: v: "${n} ${v}") cfg.extraOptionOverrides)
            ++ (optional (cfg.includes != [ ]) ''
              Include ${concatStringsSep " " cfg.includes}
            '')
            ++ (map (block: matchBlockStr block.name block.data) matchBlocks)
          )}

          Host *
            ForwardAgent ${lib.hm.booleans.yesNo cfg.forwardAgent}
            Compression ${lib.hm.booleans.yesNo cfg.compression}
            ServerAliveInterval ${toString cfg.serverAliveInterval}
            ServerAliveCountMax ${toString cfg.serverAliveCountMax}
            HashKnownHosts ${lib.hm.booleans.yesNo cfg.hashKnownHosts}
            UserKnownHostsFile ${cfg.userKnownHostsFile}
            ControlMaster ${cfg.controlMaster}
            ControlPath ${cfg.controlPath}
            ControlPersist ${cfg.controlPersist}

            ${replaceStrings ["\n"] ["\n  "] cfg.extraConfig}
        '';
      in
      config.lib.dag.entryAfter [ "writeBoundary" ] ''                                                                                                                                       
        install -m600 -D ${cfgFile} $HOME/.ssh/config                                                                                                                                      
      '';

    warnings = mapAttrsToList
      (n: v: "The SSH config match block `programs.ssh.matchBlocks.${n}` sets both of the host and match options.\nThe match option takes precedence.")
      (filterAttrs (n: v: v.data.host != null && v.data.match != null) cfg.matchBlocks);
  };
}
