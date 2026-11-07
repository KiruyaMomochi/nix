# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome"]
# ///
"""Hisense HMC300T cloud and mainboard protocol codecs."""
import base64
import hashlib
import hmac
import json
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

# Public sample key from Chipintelli CI230X-WIFI-SDK (hisense_iot/hisense_main_task.h).
FACTORY_KEY = b"6ecefdcd7aac8d64"

COMMAND_HEADER = bytes.fromhex("f4f500404b00000101fe010000650000")
FRAME_TRAILER = bytes.fromhex("f4fb")


def encode_frame(obj):
    data = json.dumps(obj, separators=(",", ":"), ensure_ascii=True).encode()
    if obj == {"id": 902}:
        return b"HS" + data + b"\r\n"
    sig = hashlib.md5(FACTORY_KEY + data).digest()[4:12].hex().encode()
    return b"HS" + data + sig + b"\r\n"


def parse_frame(frame):
    if not frame.startswith(b"HS") or not frame.endswith(b"\r\n"):
        raise ValueError("Invalid HS envelope")
    text = frame[2:-2].decode("ascii")
    obj, end = json.JSONDecoder().raw_decode(text)
    data, signature = text[:end].encode(), text[end:]
    expected = hashlib.md5(FACTORY_KEY + data).digest()[4:12].hex()
    if not (obj == {"id": 902} and signature == "") and not hmac.compare_digest(signature, expected):
        raise ValueError("Invalid factory-key signature")
    return obj


def session_key_from_102(value):
    raw = AES.new(FACTORY_KEY, AES.MODE_ECB).decrypt(base64.b64decode(value, validate=True))
    key = unpad(raw, 16)
    if len(key) != 16:
        raise ValueError("Expected 16-byte ASCII session key")
    key.decode("ascii")
    return key


def encrypt_command(raw, key):
    status = decode_status(base64.b64encode(raw).decode())
    if not status["length_valid"] or not status["checksum_valid"]:
        raise ValueError("Invalid mainboard length or checksum")
    if raw[2] != 0:
        raise ValueError("Command must have module-to-AC direction 00")
    return base64.b64encode(AES.new(key, AES.MODE_ECB).encrypt(pad(raw, 16))).decode()


def decrypt_command(value, key):
    raw = unpad(AES.new(key, AES.MODE_ECB).decrypt(base64.b64decode(value, validate=True)), 16)
    info = decode_status(base64.b64encode(raw).decode())
    if not info["length_valid"] or not info["checksum_valid"]:
        raise ValueError("Invalid decrypted command length or checksum")
    return raw


def decode_status(value):
    raw = base64.b64decode(value, validate=True)
    if len(raw) < 18 or raw[:2] != b"\xf4\xf5" or raw[-2:] != b"\xf4\xfb":
        raise ValueError("Not a complete plaintext mainboard frame")
    checksum = int.from_bytes(raw[-4:-2], "big")
    fields = {
        f"b{i}": raw[i]
        for i in (16, 17, 18, 19, 20, 26, 31, 32, 33, 34, 35, 36, 37, 41, 42, 43, 44, 45, 80, 84)
        if i < len(raw) - 4
    }
    result = {
        "encoding": "base64-plaintext",
        "length": len(raw),
        "length_valid": len(raw) == raw[4] + 9,
        "class": raw[13],
        "checksum": checksum,
        "checksum_valid": checksum == (sum(raw[2:-4]) & 0xFFFF),
        "hex": raw.hex(),
        "raw_fields": fields,
    }
    if raw[13] == 0x66 and len(raw) >= 42:
        result["summary"] = {
            "power": bool(raw[18] & 0x08),
            "mode_byte": raw[18],
            "fan_byte": raw[16],
            "target_temp_c": raw[19],
            "indoor_temp_c": raw[20],
            "swing_vertical": bool(raw[35] & 0x80),
            "swing_horizontal": bool(raw[35] & 0x40),
            "swing_angle_slot": (raw[34] >> 1) & 0x07,
            "display_on": bool(raw[37] & 0x80),
        }
    return result


def build_command(
    *,
    power=None,
    mode=None,
    temp_c=None,
    swing=None,
    angle=None,
    overrides=None,
):
    frame = bytearray(84)
    frame[:16] = COMMAND_HEADER
    frame[23] = 0x04
    frame[27] = 0x01

    if mode is not None:
        if mode == "heat":
            frame[18] = 0x3C
        elif mode == "cool":
            frame[18] = 0x5C
        else:
            raise ValueError(f"Unsupported mode: {mode}")

    if power is not None:
        if power == "on":
            if frame[18] == 0:
                frame[18] = 0x0C
        elif power == "off":
            if mode is not None:
                raise ValueError("Cannot combine --power off with --mode")
            frame[18] = 0x04
        else:
            raise ValueError(f"Unsupported power state: {power}")

    if temp_c is not None:
        if not (16 <= int(temp_c) <= 30):
            raise ValueError("temp_c must be between 16 and 30")
        if frame[18] == 0:
            frame[18] = 0x0C
        frame[19] = int(temp_c) * 2 + 1
        frame[45] = 0x01

    if angle is not None:
        if not (1 <= int(angle) <= 5):
            raise ValueError("angle must be between 1 and 5")
        frame[31] = (int(angle) << 1) | 1
        if swing is None:
            frame[32] = 0x40

    if swing is not None:
        if swing == "on":
            frame[32] = 0xC0
        elif swing == "off":
            frame[32] = 0x40
        else:
            raise ValueError(f"Unsupported swing state: {swing}")

    if overrides:
        for offset, value in overrides.items():
            idx = int(offset)
            val = int(value)
            if not (16 <= idx < 80) or not (0 <= val <= 0xFF):
                raise ValueError(f"Invalid override byte {idx}={val}")
            frame[idx] = val

    frame[80:82] = (sum(frame[2:80]) & 0xFFFF).to_bytes(2, "big")
    frame[82:84] = FRAME_TRAILER
    return bytes(frame)
