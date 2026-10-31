{ pkgs, ... }:
let
  # Measured on this unit: the fan stays stopped at pwm <= 20, spins up from
  # standstill at 30 (~780 rpm), 60 ≈ 1570 rpm, 100 ≈ 2500 rpm, 255 ≈ 5300 rpm.
  # The EC curve never goes below ~1900 rpm, which is what we want to avoid.
  fanCurve = pkgs.writeShellApplication {
    name = "saren-fan-curve";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Fan stops below OFF_AT, restarts above ON_AT; in between it keeps its
      # previous state so it doesn't flap around one temperature.
      ON_AT=55
      OFF_AT=48
      MIN_PWM=30   # lowest speed that starts reliably
      FULL_AT=85   # pwm 255 from here up

      chip() {
        for d in /sys/class/hwmon/hwmon*; do
          [ "$(cat "$d/name")" = "$1" ] && { echo "$d"; return; }
        done
        echo "hwmon chip $1 not found" >&2
        exit 1
      }
      fan=$(chip gpdfan)
      temp=$(chip k10temp)/temp1_input

      on=0
      while true; do
        # Anything unreadable: bail out, ExecStopPost hands the fan to the EC.
        t=$(( $(cat "$temp") / 1000 ))
        if [ "$t" -ge "$ON_AT" ]; then on=1; elif [ "$t" -lt "$OFF_AT" ]; then on=0; fi

        if [ "$on" -eq 0 ]; then
          pwm=0
        elif [ "$t" -ge "$FULL_AT" ]; then
          pwm=255
        else
          # MIN_PWM up to ON_AT (also while cooling back down to OFF_AT),
          # then linear to 255 at FULL_AT.
          span=$(( FULL_AT - ON_AT ))
          pwm=$(( MIN_PWM + (255 - MIN_PWM) * (t > ON_AT ? t - ON_AT : 0) / span ))
        fi

        # Re-assert manual mode every round: the EC may take over after resume.
        [ "$(cat "$fan/pwm1_enable")" = 1 ] || echo 1 > "$fan/pwm1_enable"
        echo "$pwm" > "$fan/pwm1"
        sleep 3
      done
    '';
  };

  # Hand the fan back to the EC curve, used whenever the loop isn't running.
  ecAuto = pkgs.writeShellScript "saren-fan-ec-auto" ''
    for d in /sys/class/hwmon/hwmon*; do
      [ "$(cat "$d/name")" = gpdfan ] && echo 2 > "$d/pwm1_enable"
    done
    exit 0
  '';
in
{
  # The gpd_fan driver has no temperature feedback in manual mode: if this
  # loop stops, the fan stays at whatever pwm it was last given. ExecStopPost
  # runs on every exit (crash, kill, stop), returning control to the EC.
  systemd.services.saren-fan = {
    description = "Quiet fan curve for GPD Pocket 4 (stop at idle)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${fanCurve}/bin/saren-fan-curve";
      ExecStopPost = ecAuto;
      Restart = "always";
      RestartSec = 5;
    };
  };

  # Give the EC its curve back while suspended, so a resume that is slow to
  # restart the loop never leaves the fan stopped.
  systemd.services.saren-fan-sleep = {
    description = "Hand the fan to the EC around suspend";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemctl stop saren-fan.service";
      ExecStop = "${pkgs.systemd}/bin/systemctl start --no-block saren-fan.service";
    };
  };
}
