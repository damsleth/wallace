#!/usr/bin/env python3
"""Extract the J614s multitouch HIDF blob from the pinned Apple restore IPSW."""

import argparse
import contextlib
import hashlib
import json
import os
import plistlib
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

IPSW_URL = (
    "https://updates.cdn-apple.com/2026SpringFCS/fullrestores/140-24263/"
    "B95838F0-6815-4F0B-A039-156526C081AD/"
    "UniversalMac_26.5.2_25F84_Restore.ipsw"
)
IPSW_SIZE = 19_769_902_281
BUILD_MANIFEST_SHA256 = (
    "a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef"
)
DEVICE_CLASS = "j614sap"
MULTITOUCH_PATH = "Firmware/J614s_Multitouch.im4p"
OUTPUT_NAME = "tpmtfw-j614s.bin"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def validate_hidf(data):
    if len(data) < 32:
        raise ValueError("HIDF output is shorter than its 32-byte header")

    magic, version, header_size, data_size, iface_offset = struct.unpack_from(
        "<4sIIII", data
    )
    if magic != b"HIDF":
        raise ValueError(f"unexpected HIDF magic: {magic!r}")
    if version != 1 or header_size != 32:
        raise ValueError(
            f"unexpected HIDF version/header: version={version} header={header_size}"
        )
    if data_size != len(data) - header_size:
        raise ValueError(
            f"truncated HIDF payload: declared={data_size} actual={len(data) - header_size}"
        )
    if iface_offset >= data_size:
        raise ValueError(
            f"HID interface offset {iface_offset} is outside {data_size}-byte payload"
        )
    return {
        "version": version,
        "header_size": header_size,
        "data_size": data_size,
        "interface_offset": iface_offset,
    }


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temp_path = Path(output.name)
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    os.chmod(temp_path, 0o644)
    os.replace(temp_path, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--asahi-installer-src",
        type=Path,
        required=True,
        help="Path to the pinned asahi-installer src/ directory",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("/private/tmp/t6040-vendorfw/vendorfw/apple"),
    )
    parser.add_argument(
        "--raw-dir",
        type=Path,
        default=Path("/private/tmp/t6040-vendorfw/raw-fud"),
    )
    parser.add_argument(
        "--metadata",
        type=Path,
        default=Path("/private/tmp/t6040-vendorfw/trackpad-j614s.json"),
    )
    args = parser.parse_args()

    sys.path.insert(0, str(args.asahi_installer_src))
    from asahi_firmware.multitouch import MultitouchFWCollection
    from urlcache import URLCache

    # URLCache's progress spinner writes to stdout. Keep stdout as clean JSON
    # for callers while retaining progress on stderr.
    with contextlib.redirect_stdout(sys.stderr):
        remote = URLCache(IPSW_URL)
        if remote.size != IPSW_SIZE:
            raise RuntimeError(f"unexpected IPSW size: {remote.size} != {IPSW_SIZE}")

        with zipfile.ZipFile(remote) as archive:
            manifest_data = archive.read("BuildManifest.plist")
            manifest_hash = sha256(manifest_data)
            if manifest_hash != BUILD_MANIFEST_SHA256:
                raise RuntimeError(
                    f"unexpected BuildManifest SHA-256: {manifest_hash}"
                )
            manifest = plistlib.loads(manifest_data)
            if (
                manifest.get("ProductVersion") != "26.5.2"
                or manifest.get("ProductBuildVersion") != "25F84"
            ):
                raise RuntimeError("restore manifest is not macOS 26.5.2 (25F84)")

            identities = [
                identity
                for identity in manifest["BuildIdentities"]
                if identity["Info"].get("DeviceClass") == DEVICE_CLASS
                and identity["Info"].get("RestoreBehavior") == "Erase"
                and identity["Info"].get("Variant") == "macOS Customer"
            ]
            if len(identities) != 1:
                raise RuntimeError(
                    f"expected one {DEVICE_CLASS} customer identity, "
                    f"got {len(identities)}"
                )

            info = identities[0]["Manifest"]["Multitouch"]["Info"]
            if (
                info.get("Path") != MULTITOUCH_PATH
                or not info.get("IsFUDFirmware")
                or info.get("IsLoadedByiBoot")
                or info.get("IsLoadedByiBootStage1")
            ):
                raise RuntimeError(f"unexpected Multitouch manifest entry: {info!r}")

            raw_data = archive.read(MULTITOUCH_PATH)

    raw_path = args.raw_dir / Path(MULTITOUCH_PATH).name
    write_atomic(raw_path, raw_data)

    with tempfile.TemporaryDirectory() as temp_dir:
        source = Path(temp_dir) / "j614s"
        source.mkdir(parents=True)
        (source / "Multitouch.im4p").write_bytes(raw_data)
        files = MultitouchFWCollection(temp_dir).files()

    matches = [(name, fw) for name, fw in files if name == f"apple/{OUTPUT_NAME}"]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected one apple/{OUTPUT_NAME} output, got {[name for name, _ in files]}"
        )

    _, firmware = matches[0]
    hidf = validate_hidf(firmware.data)
    output_path = args.output_dir / OUTPUT_NAME
    write_atomic(output_path, firmware.data)

    result = {
        "product_version": manifest["ProductVersion"],
        "product_build": manifest["ProductBuildVersion"],
        "device_class": DEVICE_CLASS,
        "ipsw_url": IPSW_URL,
        "ipsw_size": IPSW_SIZE,
        "build_manifest_sha256": BUILD_MANIFEST_SHA256,
        "source_member": MULTITOUCH_PATH,
        "source_size": len(raw_data),
        "source_sha256": sha256(raw_data),
        "output": str(output_path),
        "output_size": len(firmware.data),
        "output_sha256": sha256(firmware.data),
        **hidf,
    }
    result_json = json.dumps(result, indent=2, sort_keys=True) + "\n"
    write_atomic(args.metadata, result_json.encode())
    print(result_json, end="")


if __name__ == "__main__":
    main()
