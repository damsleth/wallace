#!/usr/bin/env python3
"""Range-extract the pinned T6041 SPTM payload from Apple's restore IPSW."""

import argparse
import contextlib
import hashlib
import json
import os
import plistlib
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
MEMBER = "Firmware/sptm.t6041.release.im4p"
MEMBER_SIZE = 192_376
MEMBER_CRC32 = 0x77F3BD1F


def sha256(data):
    return hashlib.sha256(data).hexdigest()


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
    parser.add_argument("--asahi-installer-src", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/private/tmp/t6040-vendorfw/raw-fud/sptm.t6041.release.im4p"),
    )
    parser.add_argument(
        "--metadata",
        type=Path,
        default=Path("/private/tmp/t6040-vendorfw/sptm-t6041.json"),
    )
    args = parser.parse_args()

    sys.path.insert(0, str(args.asahi_installer_src))
    from urlcache import URLCache

    with contextlib.redirect_stdout(sys.stderr):
        remote = URLCache(IPSW_URL)
        if remote.size != IPSW_SIZE:
            raise RuntimeError(f"unexpected IPSW size: {remote.size}")
        with zipfile.ZipFile(remote) as archive:
            manifest_data = archive.read("BuildManifest.plist")
            if sha256(manifest_data) != BUILD_MANIFEST_SHA256:
                raise RuntimeError("unexpected BuildManifest SHA-256")
            manifest = plistlib.loads(manifest_data)
            if (
                manifest.get("ProductVersion") != "26.5.2"
                or manifest.get("ProductBuildVersion") != "25F84"
            ):
                raise RuntimeError("restore manifest is not macOS 26.5.2 (25F84)")
            info = archive.getinfo(MEMBER)
            if info.file_size != MEMBER_SIZE or info.CRC != MEMBER_CRC32:
                raise RuntimeError(
                    f"unexpected member metadata: size={info.file_size} CRC={info.CRC:#x}"
                )
            data = archive.read(info)

    write_atomic(args.output, data)
    result = {
        "product_version": manifest["ProductVersion"],
        "product_build": manifest["ProductBuildVersion"],
        "ipsw_url": IPSW_URL,
        "ipsw_size": IPSW_SIZE,
        "build_manifest_sha256": BUILD_MANIFEST_SHA256,
        "source_member": MEMBER,
        "source_size": len(data),
        "source_crc32": f"{MEMBER_CRC32:08x}",
        "source_sha256": sha256(data),
        "output": str(args.output),
    }
    encoded = (json.dumps(result, indent=2, sort_keys=True) + "\n").encode()
    write_atomic(args.metadata, encoded)
    print(encoded.decode(), end="")


if __name__ == "__main__":
    main()
