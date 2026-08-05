"""
SMART disk health source for hardware poller.

Polls NVMe/SATA disk SMART attributes via smartctl.
"""

import json
import logging
import subprocess

log = logging.getLogger("hardware-poller.smart")


class SmartSource:
    """SMART disk health metrics source."""

    def setup(self, config: dict, session_state: dict, credentials: dict[str, str]):
        """Initialize SMART source."""
        devices = config.get("devices", [])
        if not devices:
            raise ValueError("No devices specified in config")
        
        log.info(f"Monitoring {len(devices)} device(s): {', '.join(devices)}")
        
        return {
            "config": config,
            "devices": devices,
        }

    def poll(self, context: dict) -> list[tuple[str, float, dict[str, str], str]]:
        """Poll SMART attributes from all devices."""
        readings = []
        
        for device in context["devices"]:
            try:
                result = subprocess.run(
                    ["smartctl", "--json=c", "-a", device],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                
                # smartctl returns non-zero for various conditions (even when data is valid)
                # Parse JSON regardless
                data = json.loads(result.stdout)
                
            except subprocess.TimeoutExpired:
                log.warning(f"smartctl timeout for {device}")
                continue
            except json.JSONDecodeError as e:
                log.warning(f"Failed to parse smartctl output for {device}: {e}")
                continue
            except Exception as e:
                log.warning(f"Failed to poll {device}: {e}")
                continue
            
            device_name = device.split("/")[-1]  # e.g. nvme0n1
            model = data.get("model_name", "unknown")
            serial = data.get("serial_number", "unknown")
            
            # NVMe SMART attributes
            if data.get("device", {}).get("protocol") == "NVMe":
                smart = data.get("nvme_smart_health_information_log", {})
                temp_sensors = smart.get("temperature_sensors", [])
                
                # Core health metrics
                if (pct_used := smart.get("percentage_used")) is not None:
                    readings.append((
                        "smart.nvme.percentage_used",
                        float(pct_used),
                        {"device": device_name, "model": model, "serial": serial},
                        "%",
                    ))
                
                if (spare := smart.get("available_spare")) is not None:
                    readings.append((
                        "smart.nvme.available_spare",
                        float(spare),
                        {"device": device_name, "model": model, "serial": serial},
                        "%",
                    ))
                
                if (temp := smart.get("temperature")) is not None:
                    readings.append((
                        "smart.nvme.temperature",
                        float(temp),
                        {"device": device_name, "model": model, "serial": serial, "sensor": "composite"},
                        "Cel",
                    ))
                
                # Additional temperature sensors
                for idx, sensor_temp in enumerate(temp_sensors, 1):
                    if sensor_temp:
                        readings.append((
                            "smart.nvme.temperature",
                            float(sensor_temp),
                            {"device": device_name, "model": model, "serial": serial, "sensor": f"sensor{idx}"},
                            "Cel",
                        ))
                
                # Error counters
                if (media_errors := smart.get("media_errors")) is not None:
                    readings.append((
                        "smart.nvme.media_errors",
                        float(media_errors),
                        {"device": device_name, "model": model, "serial": serial},
                        "",
                    ))
                
                if (unsafe_shutdowns := smart.get("unsafe_shutdowns")) is not None:
                    readings.append((
                        "smart.nvme.unsafe_shutdowns",
                        float(unsafe_shutdowns),
                        {"device": device_name, "model": model, "serial": serial},
                        "",
                    ))
                
                # Usage stats
                if (power_on_hours := smart.get("power_on_hours")) is not None:
                    readings.append((
                        "smart.nvme.power_on_hours",
                        float(power_on_hours),
                        {"device": device_name, "model": model, "serial": serial},
                        "h",
                    ))
                
                if (data_written := smart.get("data_units_written")) is not None:
                    # data_units_written is in units of 512KB (1000 * 512 bytes)
                    readings.append((
                        "smart.nvme.data_written_bytes",
                        float(data_written) * 512000,
                        {"device": device_name, "model": model, "serial": serial},
                        "By",
                    ))
                
                if (data_read := smart.get("data_units_read")) is not None:
                    readings.append((
                        "smart.nvme.data_read_bytes",
                        float(data_read) * 512000,
                        {"device": device_name, "model": model, "serial": serial},
                        "By",
                    ))
            
            # SATA/SAS SMART attributes (if needed in the future)
            # elif data.get("device", {}).get("type") in ["sat", "scsi"]:
            #     ...
        
        return readings

    def poll_logs(self, context: dict) -> list[tuple[str, str, dict[str, str], int | None]]:
        """SMART source doesn't emit logs."""
        return []
