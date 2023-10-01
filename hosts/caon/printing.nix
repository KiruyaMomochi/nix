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
  ];
  services.avahi.enable = true;

  # services.avahi.ipv6 = false;
  services.avahi.extraConfig = ''
    [publish]
    publish-aaaa-on-ipv4=no
    add-service-cookie=yes
  '';

  services.avahi.nssmdns = true;

  # for a WiFi printer
  services.avahi.openFirewall = true;
  services.avahi.publish = {
    enable = true;
    userServices = true;
    hinfo = true;
    workstation = true;
    domain = true;
  };
  services.printing.browsing = true;
  services.printing.listenAddresses = [ "*:631" ]; # Not 100% sure this is needed and you might want to restrict to the local network
  services.printing.allowFrom = [ "all" ]; # this gives access to anyone on the interface you might want to limit it see the official documentation
  # services.printing.defaultShared = true; # If you want
}
