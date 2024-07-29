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

    nvidia =
      let
        # /nix/store/qxf6anli54ij0q1sdlnlgx9hyl658a4v-source/nixos/modules/hardware/video/nvidia.nix:105:38
        nvidiaEnabled = (lib.elem "nvidia" config.services.xserver.videoDrivers);
        nvidia_x11 = if nvidiaEnabled || config.hardware.nvidia.datacenter.enable then config.hardware.nvidia.package else null;
      in
      mkOption {
        type = types.bool;
        example = true;
        default = if nvidia_x11 != null then config.hardware.nvidia.modesetting.enable else false;
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
          # FIXME: Remove this when `docker` gets a update
          package = pkgs.docker_26;
          daemon.settings.features.cdi = true;

          rootless = {
            enable = true;
            # FIXME: Remove this when `docker` gets a update
            package = pkgs.docker_26;
            daemon.settings = {
              # https://github.com/NVIDIA/nvidia-container-toolkit/issues/434
              # https://github.com/moby/moby/issues/47676
              features.cdi = true;
            };
          };
        };
      })

      (mkIf config.virtualisation.podman.enable {
        # https://github.com/NixOS/nixpkgs/issues/226365
        networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 5353 ];
        environment.systemPackages = [ pkgs.podman-compose ];

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
