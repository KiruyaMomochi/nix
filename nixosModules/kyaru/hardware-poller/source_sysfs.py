"""
sysfs source for hardware poller.

Reads battery / AC state from /sys/class/power_supply and every hwmon chip's
temperatures, fan speeds and pwm values from /sys/class/hwmon. Chips are
labelled by their `name` file, so hwmonN renumbering across boots doesn't
matter.
"""

import logging
from pathlib import Path

log = logging.getLogger("hardware-poller.sysfs")

POWER_SUPPLY = Path("/sys/class/power_supply")
HWMON = Path("/sys/class/hwmon")

STATUS = {"Charging": 1.0, "Discharging": -1.0}


def read(path: Path) -> str | None:
    try:
        return path.read_text().strip()
    except OSError:
        return None


def read_num(path: Path) -> float | None:
    raw = read(path)
    if raw is None:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


class SysfsSource:
    """Battery and hwmon readings straight from sysfs."""

    def setup(self, config: dict, session_state: dict, credentials: dict[str, str]):
        return {"config": config}

    def poll(self, context: dict) -> list[tuple[str, float, dict[str, str], str]]:
        readings = []

        for supply in sorted(POWER_SUPPLY.iterdir()):
            kind = read(supply / "type")
            attrs = {"supply": supply.name}
            if kind == "Mains":
                if (online := read_num(supply / "online")) is not None:
                    readings.append(("power_supply.online", online, attrs, ""))
            elif kind == "Battery":
                # power_now / energy_* are in µW / µWh.
                for key, metric, unit, scale in [
                    ("power_now", "battery.power", "W", 1e-6),
                    ("energy_now", "battery.energy", "Wh", 1e-6),
                    ("energy_full", "battery.energy_full", "Wh", 1e-6),
                    ("energy_full_design", "battery.energy_full_design", "Wh", 1e-6),
                    ("capacity", "battery.capacity", "%", 1.0),
                ]:
                    if (value := read_num(supply / key)) is not None:
                        readings.append((metric, value * scale, attrs, unit))
                status = read(supply / "status") or ""
                readings.append(("battery.status", STATUS.get(status, 0.0), attrs, ""))

        for chip in sorted(HWMON.iterdir()):
            name = read(chip / "name") or chip.name
            for f in sorted(chip.glob("temp*_input")):
                sensor = f.name.removesuffix("_input")
                if (value := read_num(f)) is None:
                    continue
                label = read(chip / f"{sensor}_label") or sensor
                readings.append(("hwmon.temperature", value / 1000,
                                 {"chip": name, "sensor": label}, "Cel"))
            for f in sorted(chip.glob("fan*_input")):
                if (value := read_num(f)) is not None:
                    readings.append(("hwmon.fan", value,
                                     {"chip": name, "sensor": f.name.removesuffix("_input")}, "{rpm}"))
            for f in sorted(chip.glob("pwm[0-9]")):
                attrs = {"chip": name, "sensor": f.name}
                if (value := read_num(f)) is not None:
                    readings.append(("hwmon.pwm", value, attrs, ""))
                if (mode := read_num(chip / f"{f.name}_enable")) is not None:
                    readings.append(("hwmon.pwm_enable", mode, attrs, ""))

        return readings

    def poll_logs(self, context: dict) -> list:
        return []
