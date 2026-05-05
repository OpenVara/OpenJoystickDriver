#!/usr/bin/env python3
"""Validate bundled controller profiles without third-party dependencies."""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
DEVICE_SCHEMA_DIR = ROOT / "Resources" / "Schemas" / "Devices"
SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/controller-profile.schema.json"
)
DEVICE_SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/device-profile.schema.json"
)

PROTOCOLS = {
    "GIP": {
        "variants": {"xboxOriginal", "xbox360", "xbox360Wireless", "xboxOne", "unknown"},
        "mapping_flags": {
            "dpadToButtons",
            "triggersToButtons",
            "sticksToNull",
            "shareButton",
            "paddles",
            "profileButton",
            "shareOffset",
        },
    },
    "Xbox360": {
        "variants": {"xbox360", "unknown"},
        "mapping_flags": {"dpadToButtons", "triggersToButtons", "sticksToNull"},
    },
    "DS3": {
        "variants": {"dualShock3", "unknown"},
        "mapping_flags": {"gyro", "accelerometer", "battery"},
    },
    "DS4": {
        "variants": {"dualShock4", "unknown"},
        "mapping_flags": {"touchpad", "gyro", "accelerometer", "battery", "lightbar"},
    },
    "GenericHID": {
        "variants": {"genericHID"},
        "mapping_flags": set(),
    },
}

BACKENDS = {"driverKitHID", "userSpaceHID", "gameControllerVirtual"}
VIRTUAL_PROFILES = {"xboxOneS"}


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def require_object(value: Any, path: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{path} must be an object")
    return value


def require_string(value: Any, path: str) -> str:
    require(isinstance(value, str) and value, f"{path} must be a non-empty string")
    return value


def require_int(value: Any, path: str, minimum: int, maximum: int | None = None) -> int:
    require(isinstance(value, int) and not isinstance(value, bool), f"{path} must be an integer")
    require(value >= minimum, f"{path} must be >= {minimum}")
    if maximum is not None:
        require(value <= maximum, f"{path} must be <= {maximum}")
    return value


def require_string_list(value: Any, path: str) -> list[str]:
    require(isinstance(value, list), f"{path} must be an array")
    result: list[str] = []
    for idx, item in enumerate(value):
        result.append(require_string(item, f"{path}[{idx}]"))
    require(len(result) == len(set(result)), f"{path} must not contain duplicates")
    return result


def validate_profile(path: pathlib.Path) -> tuple[int, int, str]:
    data = json.loads(path.read_text())
    root = require_object(data, "$")
    require(
        root.get("$schema") in {"../../../../../Resources/Schemas/controller-profile.schema.json", SCHEMA_ID},
        "$schema must reference controller-profile.schema.json",
    )
    require_string(root.get("profile_version"), "profile_version")

    identity = require_object(root.get("identity"), "identity")
    vid = require_int(identity.get("vendor_id"), "identity.vendor_id", 1, 65535)
    pid = require_int(identity.get("product_id"), "identity.product_id", 0, 65535)
    require_string(identity.get("name"), "identity.name")
    require_string(identity.get("short_name"), "identity.short_name")

    input_section = require_object(root.get("input"), "input")
    transport = require_string(input_section.get("transport"), "input.transport")
    require(transport in {"usb", "hid"}, "input.transport must be usb or hid")
    usb = require_object(input_section.get("usb"), "input.usb")
    usb_class = require_int(usb.get("class"), "input.usb.class", 0, 255)
    require(usb_class in {3, 255}, "input.usb.class must be 3 or 255")
    require_int(usb.get("interface"), "input.usb.interface", 0)
    configuration = usb.get("configuration")
    if configuration is not None:
        require(configuration == "set1BeforeClaim", "input.usb.configuration is unknown")
    settle_ms = usb.get("post_handshake_settle_ms", 0)
    require_int(settle_ms, "input.usb.post_handshake_settle_ms", 0)
    endpoints = usb.get("endpoints")
    if endpoints is not None:
        endpoint_obj = require_object(endpoints, "input.usb.endpoints")
        require_int(endpoint_obj.get("in"), "input.usb.endpoints.in", 0, 255)
        require_int(endpoint_obj.get("out"), "input.usb.endpoints.out", 0, 255)
    elif transport == "usb":
        raise ValidationError("input.usb.endpoints is required for usb transport")

    protocol = require_object(root.get("protocol"), "protocol")
    driver = require_string(protocol.get("driver"), "protocol.driver")
    require(driver in PROTOCOLS, f"protocol.driver is unsupported: {driver}")
    variant = require_string(protocol.get("variant"), "protocol.variant")
    require(variant in PROTOCOLS[driver]["variants"], f"protocol.variant {variant} is invalid for {driver}")
    flags = require_string_list(protocol.get("mapping_flags", []), "protocol.mapping_flags")
    invalid_flags = sorted(set(flags) - PROTOCOLS[driver]["mapping_flags"])
    require(not invalid_flags, f"protocol.mapping_flags invalid for {driver}: {', '.join(invalid_flags)}")

    output = require_object(root.get("output"), "output")
    virtual_profile = require_string(output.get("virtual_profile"), "output.virtual_profile")
    require(virtual_profile in VIRTUAL_PROFILES, f"output.virtual_profile is unsupported: {virtual_profile}")
    backends = require_string_list(output.get("preferred_backends"), "output.preferred_backends")
    require(backends, "output.preferred_backends must not be empty")
    invalid_backends = sorted(set(backends) - BACKENDS)
    require(not invalid_backends, f"output.preferred_backends invalid: {', '.join(invalid_backends)}")

    return vid, pid, driver


def validate_device_schema(path: pathlib.Path) -> tuple[int, int]:
    data = json.loads(path.read_text())
    root = require_object(data, "$")
    require(root.get("$schema") == DEVICE_SCHEMA_ID, "$schema must reference device-profile.schema.json")
    vid = require_int(root.get("vendor_id"), "vendor_id", 1, 65535)
    pid = require_int(root.get("product_id"), "product_id", 0, 65535)
    require_string(root.get("name"), "name")
    protocol = require_string(root.get("protocol"), "protocol")
    require(protocol in PROTOCOLS, f"protocol is unsupported: {protocol}")

    usb = require_object(root.get("usb"), "usb")
    require_int(usb.get("interface"), "usb.interface", 0)
    usb_class = require_int(usb.get("class"), "usb.class", 0, 255)
    require(usb_class in {3, 255}, "usb.class must be 3 or 255")
    configuration = usb.get("configuration")
    if configuration is not None:
        require(configuration == "set1BeforeClaim", "usb.configuration is unknown")
    settle_ms = usb.get("post_handshake_settle_ms", 0)
    require_int(settle_ms, "usb.post_handshake_settle_ms", 0)
    endpoints = require_object(usb.get("endpoints"), "usb.endpoints")
    for direction in ("in", "out"):
        endpoint = require_object(endpoints.get(direction), f"usb.endpoints.{direction}")
        require_int(endpoint.get("address"), f"usb.endpoints.{direction}.address", 0, 255)
        endpoint_type = require_string(endpoint.get("type"), f"usb.endpoints.{direction}.type")
        require(endpoint_type in {"interrupt", "bulk"}, f"usb.endpoints.{direction}.type is unsupported")
        require_int(endpoint.get("max_packet"), f"usb.endpoints.{direction}.max_packet", 1)

    init_sequence = root.get("init_sequence")
    require(isinstance(init_sequence, list) and init_sequence, "init_sequence must be a non-empty array")
    input_commands = require_object(root.get("input_commands"), "input_commands")
    require("input" in input_commands, "input_commands.input is required")
    return vid, pid


def main() -> int:
    profiles = sorted(PROFILE_DIR.glob("*.json"))
    if not profiles:
        print(f"ERROR: no controller profiles found in {PROFILE_DIR}", file=sys.stderr)
        return 1

    seen: dict[tuple[int, int], pathlib.Path] = {}
    profile_protocols: dict[tuple[int, int], str] = {}
    failures = 0
    for profile in profiles:
        try:
            vid, pid, driver = validate_profile(profile)
            key = (vid, pid)
            if key in seen:
                raise ValidationError(f"duplicate VID/PID also in {seen[key].name}")
            seen[key] = profile
            profile_protocols[key] = driver
            print(f"[OK] {profile.relative_to(ROOT)}")
        except Exception as exc:
            failures += 1
            print(f"[FAIL] {profile.relative_to(ROOT)}: {exc}", file=sys.stderr)

    device_schemas = sorted(DEVICE_SCHEMA_DIR.glob("*.json"))
    device_schema_keys: dict[tuple[int, int], pathlib.Path] = {}
    for schema in device_schemas:
        try:
            key = validate_device_schema(schema)
            if key not in seen:
                raise ValidationError("device schema VID/PID has no matching controller profile")
            if key in device_schema_keys:
                raise ValidationError(f"duplicate device schema also in {device_schema_keys[key].name}")
            device_schema_keys[key] = schema
            print(f"[OK] {schema.relative_to(ROOT)}")
        except Exception as exc:
            failures += 1
            print(f"[FAIL] {schema.relative_to(ROOT)}: {exc}", file=sys.stderr)

    for key, driver in sorted(profile_protocols.items()):
        if driver == "GIP" and key not in device_schema_keys:
            failures += 1
            profile = seen[key]
            print(
                f"[FAIL] {profile.relative_to(ROOT)}: GIP controller is missing Resources/Schemas/Devices/*.json",
                file=sys.stderr,
            )

    if failures:
        print(f"FAILED: {failures} profile(s) invalid", file=sys.stderr)
        return 1
    print(f"Validated {len(profiles)} controller profile(s) and {len(device_schemas)} device schema(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
