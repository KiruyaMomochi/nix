{ pkgs, ... }:

# Face unlock with the HM1092 IR camera (the one Windows Hello uses).
# Enrol with `sudo howdy add`. Faces enrolled under the RGB camera won't match.
let
  howdy = pkgs.howdy.overrideAttrs (old: {
    # opencv4Full turns on Intel IPP (ICV), which doesn't exist on aarch64.
    passthru = old.passthru // {
      pythonDeps = map (p: if p == "opencv4Full" then "opencv4" else p) old.passthru.pythonDeps;
    };
    postInstall = old.postInstall + ''
      patch -p1 -d $out/lib/howdy < ${./howdy-hm1092-plugin.patch}
      install -m644 ${./howdy-ir-reader.py} $out/lib/howdy/recorders/ir_reader.py
      substituteInPlace $out/lib/howdy/recorders/ir_reader.py \
        --replace-fail @libcameraPython@ ${pkgs.libcamera}/${pkgs.python3.sitePackages}
    '';
  });
in
{
  services.howdy = {
    enable = true;
    package = howdy;
    control = "sufficient";
    # No ACPI on this machine, so the lid check only logs "Failed to read files from glob".
    settings.core.abort_if_lid_closed = false;
    settings.video = {
      recording_plugin = "hm1092";
      # Only checked for existence; the recorder finds the sensor through libcamera.
      device_path = "/dev/media0";
      # Percentage of near-black pixels that rejects a frame. IR frames are mostly black.
      dark_threshold = 90;
    };
  };

  # Face only where it's convenient; login keeps the password so kwallet unlocks.
  security.pam.howdy.enable = false;
  security.pam.services.sudo.howdy.enable = true;
  security.pam.services.polkit-1.howdy.enable = true;

  # The lock screen authenticates as the user, so the user has to be able to light the IR LED.
  services.udev.extraRules = ''
    SUBSYSTEM=="leds", KERNEL=="ir:flash", RUN+="${pkgs.coreutils}/bin/chgrp video /sys%p/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/brightness"
  '';
}
