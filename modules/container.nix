{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.kyaru.containers;
in
{
  options.kyaru.containers = {
    patch = mkOption {
      type = types.bool;
      example = false;
      default = true;
      description = ''
        Enable Kyaru's containers patch
      '';
    };

    nvidia = mkOption {
      type = types.bool;
      example = true;
      default = config.hardware.nvidia.modesetting.enable;
      description = ''
        Enable NVIDIA support
      '';
    };

    btrfs = mkOption {
      type = types.bool;
      example = true;
      default = config.fileSystems."/".fsType == "btrfs";
      description = ''
        Use btrfs driver
      '';
    };
  };

  config =
    mkIf cfg.patch (mkMerge [
      (mkIf config.virtualisation.docker.enable {
        # https://github.com/NixOS/nixpkgs/issues/226365
        networking.firewall.interfaces."docker*".allowedUDPPorts = [ 53 5353 ];

        # Docker
        virtualisation.docker = {
          # extraOptions = "--iptables=False";
          rootless = {
            enable = true;
            setSocketVariable = true;
          };
        };
      })

      (mkIf config.virtualisation.podman.enable {
        # https://github.com/NixOS/nixpkgs/issues/226365
        networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 5353 ];
        # Podman
        virtualisation.podman = {
          # Required for containers under podman-compose to be able to talk to each other.
          defaultNetwork.settings = {
            dns_enabled = true;
          };
        };
        # https://github.com/NixOS/nixpkgs/issues/226365
      })

      (mkIf config.virtualisation.containers.enable {
        virtualisation.containers = {
          storage.settings = {
            storage = {
              driver = mkDefault "overlay";
              graphroot = "/var/lib/containers/storage";
              runroot = "/run/containers/storage";
            };
          };
        };
      })

      (mkIf cfg.btrfs
        (
          mkMerge [
            (
              mkIf config.virtualisation.docker.enable
                {
                  virtualisation.docker.storageDriver = "btrfs";
                }
            )
            (
              mkIf config.virtualisation.podman.enable
                {
                  virtualisation.podman.extraPackages = [ pkgs.btrfs-progs ];
                }
            )
            (
              mkIf config.virtualisation.containers.enable
                {
                  virtualisation.containers.storage.settings.storage.driver = "btrfs";
                }
            )
          ])
      )

      (mkIf cfg.nvidia {
        environment.systemPackages = [ pkgs.libnvidia-container ];
        systemd.user.services.docker.path = [ pkgs.nvidia-docker ];

        # From nixpkgs changelog:
        # `virtualisation.docker.enableNvidia` and `virtualisation.podman.enableNvidia` options are deprecated. 
        # `hardware.nvidia-container-toolkit.enable` should be used instead. This option will expose GPUs on containers with the `--device` CLI option.
        # This is supported by Docker 25, Podman 3.2.0 and Singularity 4. Any container runtime that supports the CDI specification will take advantage of this feature.
        hardware.nvidia-container-toolkit.enable = true;
      })
    ]);
}
