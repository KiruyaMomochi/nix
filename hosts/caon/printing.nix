{ config, pkgs, lib, ... }:
{
  networking.firewall = {
    allowedTCPPorts = [
      # printing
      631
    ];
    allowedUDPPorts = [
      # mdns
      5353
      # printing
      631
    ];
  };

  # Printer
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [
    gutenprint
    gutenprintBin
    hplipWithPlugin
    kyaru.ptouch-driver-ppds
  ];
  # services.printing.extraConf = ''
  #   FileDevice Yes
  # '';
  services.avahi.enable = true;

  # services.avahi.ipv6 = false;
  services.avahi.extraConfig = ''
    [publish]
    publish-aaaa-on-ipv4=no
    add-service-cookie=yes
  '';

  services.avahi.nssmdns4 = true;

  # for a WiFi printer
  services.avahi.openFirewall = true;
  services.avahi.publish = {
    enable = true;
    userServices = true;
    hinfo = true;
    workstation = true;
    domain = true;
  };
  services.printing = {
    browsing = true;
    listenAddresses = [ "*:631" ]; # Not 100% sure this is needed and you might want to restrict to the local network
    allowFrom = [ "all" ]; # this gives access to anyone on the interface you might want to limit it see the official documentation
    # defaultShared = true; # If you want
    openFirewall = true;
  };

  # Scan
  hardware.sane.enable = true;
  hardware.sane.extraBackends = [ pkgs.sane-airscan pkgs.hplipWithPlugin ];
  services.ipp-usb.enable = true;

  # Samba and wsdd
  services.samba-wsdd.enable = true;
  services.samba-wsdd.openFirewall = true;

  # https://nixos.wiki/wiki/Samba#Printer_sharing
  services.samba = {
    enable = true;
    package = pkgs.sambaFull;
    openFirewall = true;
    securityType = "user";

    extraConfig = ''
      load printers = yes
      printing = cups
      printcap name = cups
    '';
    shares = {
      printers = {
        comment = "All Printers";
        path = "/var/spool/samba";
        public = "yes";
        browseable = "yes";
        # to allow user 'guest account' to print.
        "guest ok" = "yes";
        writable = "no";
        printable = "yes";
        "create mode" = 0700;
      };
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/spool/samba 1777 root root -"
  ];
}
