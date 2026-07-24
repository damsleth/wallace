#!/usr/bin/env python3
"""Build a pinned, host-local J614s firmware corpus from macOS 25F84."""

import argparse
import contextlib
import gzip
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tarfile
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
ASAHI_INSTALLER_COMMIT = "c53d66dc71937efa2530d4323c81addaebb5a09b"
BASE_SYSTEM_AEA_SHA256 = (
    "fe56fcb5a0aa2e0214dbe69f108ed35670bf33d32fdc346c6efb1784cf7705cd"
)
BASE_SYSTEM_DMG_SHA256 = (
    "48067a9bfc7714bde6e61223399bff2aa7bd1fe1b2c1f24c86d455ea801b1301"
)
KERNELCACHE_SHA256 = (
    "4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b"
)

FUD_SKIP_KEYS = {
    "BaseSystem",
    "OS",
    "Ap,SystemVolumeCanonicalMetadata",
    "StaticTrustCache",
    "SystemVolume",
}
EXPECTED_FUD = {
    "Ap,DCP2": "Firmware/dcp/t604xdcp.im4p",
    "Ap,SecurePageTableMonitor": "Firmware/sptm.t6041.release.im4p",
    "Ap,TrustedExecutionMonitor": "Firmware/txm.macosx.release.im4p",
    "InputDevice": "Firmware/J614S_InputDevice.im4p",
    "Multitouch": "Firmware/J614s_Multitouch.im4p",
}

EXPECTED_VENDORFW = {
    "apple/isp_1820_01XX.dat": "23b7f76aca7e0ea8b462d8bc20a7a218b2d86015d62867fca6c5f38cdbf36e1d",
    "apple/isp_1822_02XX.dat": "1292c640b07497fed42f035319462a212108fd4c3fba2f3883226ef31bd5107f",
    "apple/isp_1921_01XX.dat": "b0c47560b845b40f8f096c82fac0f7adbaa171fbd10c84dc6a119593e2ab1d12",
    "apple/isp_1922_02XX.dat": "9483c3fa909d86debb8924e07be094335be75c9b2c63b7dddcbb727f2483363d",
    "apple/isp_8720_01XX.dat": "c398e4922eae2ad5acfdb312e4f9149482131440cfebda93fec0a38208fec12f",
    "apple/isp_8723_01XX.dat": "d05e1befd2a54dba750a24709bf9bd2bbb55a158b91ce047810292b0c4e17ce4",
    "apple/tpmtfw-j614s.bin": "a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2",
    "asmedia/asm2214a-apple.bin": "691bb72aa21fe609fa7565c7f4478b078bb8c4161edd441326ce0c008e5f74bd",
    "brcm/brcmbt4388c2-apple,mriya-u.bin": "842258ff94948558073010494f0d8f5ab6d1d539e1b07b7b37790ca4cd9c923e",
    "brcm/brcmbt4388c2-apple,mriya-u.ptb": "6f0f1002c45ef7feffe03aef9f4927ecdfdac3baefafeffda742d51ff2752d29",
    "brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-a.txt": "02137cf6fec8e437206f23b6542a9a7cdc8ca39a2ea9b2e07ce2d4bc5409913b",
    "brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.txt": "4d0f3187f2e0dd708f5271bffdc43cc63e4d68a3c3449d8c8ff580286eb75bf0",
    "brcm/brcmfmac4388c0-pcie.apple,mriya.bin": "cd49096c0b0f95caf5e0fd53e1460b8b6ed21f4aba9c314bc0602d6bec77f4bb",
    "brcm/brcmfmac4388c0-pcie.apple,mriya.clm_blob": "822fd43c5502d77d1e7c910e44255bc878b0fa5b046b5133450f6f928098f26b",
    "brcm/brcmfmac4388c0-pcie.apple,mriya.sig": "97ce17756689483a468e52bab27978023727cb7e8b3e372f23a36d410366cae6",
    "brcm/brcmfmac4388c0-pcie.apple,mriya.txcap_blob": "7a588168ee5ab1c891e0fadaef56592e84b6c766f91e92b9f08820b822f243fb",
    "brcm/brcmfmac4388c2-pcie.apple,mriya-WLMT-a.txt": "a30428331a385392a04d535d5c106bd2517de0bfb244c58e4e2464c937ff013c",
    "brcm/brcmfmac4388c2-pcie.apple,mriya-WLMT-u.txt": "203251922cfcf95f2233290d75def5ae88e41dfda77af36d8426d9d6db1db3d9",
    "brcm/brcmfmac4388c2-pcie.apple,mriya.bin": "7cfae8622feeb119c756ae707d26f3a94f1cde44becefacf27ecf1fdc586d93b",
    "brcm/brcmfmac4388c2-pcie.apple,mriya.clm_blob": "af8df65b766a6e2c450892819ecf8422289463e342aa748532c110032140f309",
    "brcm/brcmfmac4388c2-pcie.apple,mriya.sig": "9abb8c1afe0413339f5eca7706150c507a7bca5d244b0a4c6f79e4c28d2ce7cf",
    "brcm/brcmfmac4388c2-pcie.apple,mriya.txcap_blob": "2ee489bb7b59b74bad259969344d513b7a6803e83f3563b2ce090df18f53a013",
}


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_bytes(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    os.chmod(path, 0o644)


def copy_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    os.chmod(destination, 0o644)


def normalized_tar(source, output):
    """Create a deterministic gzip-compressed tar containing source as raw/."""

    with output.open("wb") as raw_output:
        with gzip.GzipFile(
            filename="", mode="wb", fileobj=raw_output, mtime=0
        ) as gzip_output:
            with tarfile.open(
                fileobj=gzip_output, mode="w", format=tarfile.PAX_FORMAT
            ) as archive:
                paths = [source]
                paths.extend(sorted(source.rglob("*"), key=lambda item: item.as_posix()))
                for path in paths:
                    relative = Path("raw") / path.relative_to(source)
                    info = archive.gettarinfo(str(path), arcname=relative.as_posix())
                    info.uid = 0
                    info.gid = 0
                    info.uname = "root"
                    info.gname = "root"
                    info.mtime = 0
                    if info.isdir():
                        info.mode = 0o755
                    elif info.isfile():
                        info.mode = 0o644
                    if info.isfile():
                        with path.open("rb") as payload:
                            archive.addfile(info, payload)
                    else:
                        archive.addfile(info)
    os.chmod(output, 0o444)


def find_identity(manifest):
    identities = [
        identity
        for identity in manifest["BuildIdentities"]
        if identity["Info"].get("DeviceClass") == DEVICE_CLASS
        and identity["Info"].get("RestoreBehavior") == "Erase"
        and identity["Info"].get("Variant") == "macOS Customer"
    ]
    if len(identities) != 1:
        raise RuntimeError(
            f"expected one {DEVICE_CLASS} customer identity, got {len(identities)}"
        )
    return identities[0]


def fetch_fud(raw_root, asahi_source):
    sys.path.insert(0, str(asahi_source))
    from urlcache import URLCache

    with contextlib.redirect_stdout(sys.stderr):
        remote = URLCache(IPSW_URL)
        if remote.size != IPSW_SIZE:
            raise RuntimeError(f"unexpected IPSW size: {remote.size}")
        with zipfile.ZipFile(remote) as archive:
            manifest_data = archive.read("BuildManifest.plist")
            if sha256_bytes(manifest_data) != BUILD_MANIFEST_SHA256:
                raise RuntimeError("unexpected BuildManifest SHA-256")
            manifest = plistlib.loads(manifest_data)
            if (
                manifest.get("ProductVersion") != "26.5.2"
                or manifest.get("ProductBuildVersion") != "25F84"
            ):
                raise RuntimeError("restore manifest is not macOS 26.5.2 (25F84)")
            identity = find_identity(manifest)

            selected = {}
            for key, value in identity["Manifest"].items():
                info = value.get("Info", {})
                path = info.get("Path", "")
                if key in FUD_SKIP_KEYS:
                    continue
                if (
                    info.get("IsFUDFirmware")
                    and not info.get("IsLoadedByiBoot")
                    and not info.get("IsLoadedByiBootStage1")
                    and path.endswith(".im4p")
                ):
                    selected[key] = path
            if selected != EXPECTED_FUD:
                raise RuntimeError(f"unexpected non-iBoot FUD set: {selected!r}")

            records = []
            fud_root = raw_root / "fud_firmware"
            machine_root = fud_root / "j614s"
            machine_root.mkdir(parents=True)
            for key, member in sorted(selected.items()):
                info = archive.getinfo(member)
                data = archive.read(info)
                destination = fud_root / member
                copy_bytes(destination, data)
                link = machine_root / f"{key}.im4p"
                link.symlink_to(Path("..") / member)
                records.append(
                    {
                        "key": key,
                        "member": member,
                        "size": len(data),
                        "zip_crc32": f"{info.CRC:08x}",
                        "sha256": sha256_bytes(data),
                    }
                )
    return records


def collect_base_system(raw_root, base_system):
    wifi_source = (
        base_system
        / "System/Library/DriverExtensions/"
        "com.apple.DriverKit-AppleBCMWLAN.dext/Firmware"
    )
    bluetooth_source = base_system / "usr/share/firmware/bluetooth"
    camera_source = base_system / "usr/sbin/appleh13camerad"
    for required in (wifi_source, bluetooth_source, camera_source):
        if not required.exists():
            raise RuntimeError(f"missing BaseSystem input: {required}")

    raw_wifi = raw_root / "firmware/wifi"
    raw_bluetooth = raw_root / "firmware/bluetooth"
    copied_wifi = []
    for source in sorted(wifi_source.rglob("*mriya*")):
        if not (source.is_file() or source.is_symlink()):
            continue
        relative = source.relative_to(wifi_source)
        copy_file(source, raw_wifi / relative)
        copied_wifi.append(relative.as_posix())
    copied_bluetooth = []
    for source in sorted(bluetooth_source.iterdir()):
        if "mriya" not in source.name.lower() or not source.is_file():
            continue
        copy_file(source, raw_bluetooth / source.name)
        copied_bluetooth.append(source.name)
    copy_file(camera_source, raw_root / "appleh13camerad")

    if len(copied_wifi) != 72:
        raise RuntimeError(f"expected 72 raw mriya WiFi files, got {len(copied_wifi)}")
    if len(copied_bluetooth) != 4:
        raise RuntimeError(
            f"expected four raw mriya Bluetooth files, got {len(copied_bluetooth)}"
        )
    return {
        "wifi_files": copied_wifi,
        "bluetooth_files": copied_bluetooth,
        "appleh13camerad": {
            "size": camera_source.stat().st_size,
            "sha256": sha256_file(camera_source),
        },
    }


def collect_vendorfw(raw_root, kernelcache, asahi_source):
    sys.path.insert(0, str(asahi_source))
    from asahi_firmware.bluetooth import BluetoothFWCollection
    from asahi_firmware.isp import ISPFWCollection
    from asahi_firmware.kernel import KernelFWCollection
    from asahi_firmware.multitouch import MultitouchFWCollection
    from asahi_firmware.wifi import WiFiFWCollection

    collections = [
        WiFiFWCollection(raw_root / "firmware/wifi").files(),
        BluetoothFWCollection(raw_root / "firmware/bluetooth").files(),
        MultitouchFWCollection(raw_root / "fud_firmware").files(),
        ISPFWCollection(raw_root).files(),
        KernelFWCollection(kernelcache).files(),
    ]
    outputs = {}
    for collection in collections:
        for name, firmware in collection:
            if name in outputs:
                raise RuntimeError(f"duplicate vendorfw output: {name}")
            outputs[name] = firmware.data

    actual = {name: sha256_bytes(data) for name, data in outputs.items()}
    if actual != EXPECTED_VENDORFW:
        missing = sorted(set(EXPECTED_VENDORFW) - set(actual))
        extra = sorted(set(actual) - set(EXPECTED_VENDORFW))
        wrong = sorted(
            name
            for name in set(actual) & set(EXPECTED_VENDORFW)
            if actual[name] != EXPECTED_VENDORFW[name]
        )
        raise RuntimeError(
            f"vendorfw regression mismatch: missing={missing}, extra={extra}, "
            f"wrong_hash={wrong}"
        )
    return outputs


def inventory_files(root, excluded=()):
    excluded = set(excluded)
    result = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(root).as_posix()
        if relative in excluded:
            continue
        result.append(
            {
                "path": relative,
                "size": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Build the pinned 25F84 J614s paired-firmware corpus"
    )
    parser.add_argument("--base-system", type=Path, required=True)
    parser.add_argument("--base-system-aea", type=Path, required=True)
    parser.add_argument("--base-system-dmg", type=Path, required=True)
    parser.add_argument("--kernelcache", type=Path, required=True)
    parser.add_argument("--asahi-installer", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/private/tmp/t6040-paired-fw-25F84"),
    )
    args = parser.parse_args()

    for path in (
        args.base_system,
        args.base_system_aea,
        args.base_system_dmg,
        args.kernelcache,
        args.asahi_installer,
    ):
        if not path.exists():
            raise SystemExit(f"input does not exist: {path}")
    if args.output.exists():
        raise SystemExit(f"refusing to overwrite output: {args.output}")

    asahi_commit = subprocess.run(
        ["git", "-C", str(args.asahi_installer), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if asahi_commit != ASAHI_INSTALLER_COMMIT:
        raise SystemExit(
            f"unexpected asahi-installer commit: {asahi_commit} "
            f"(expected {ASAHI_INSTALLER_COMMIT})"
        )
    source_hashes = {
        "base_system_aea": sha256_file(args.base_system_aea),
        "base_system_dmg": sha256_file(args.base_system_dmg),
        "kernelcache": sha256_file(args.kernelcache),
    }
    expected_source_hashes = {
        "base_system_aea": BASE_SYSTEM_AEA_SHA256,
        "base_system_dmg": BASE_SYSTEM_DMG_SHA256,
        "kernelcache": KERNELCACHE_SHA256,
    }
    if source_hashes != expected_source_hashes:
        raise SystemExit(
            f"source hash mismatch: actual={source_hashes!r} "
            f"expected={expected_source_hashes!r}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(
        tempfile.mkdtemp(
            prefix=f".{args.output.name}.", dir=str(args.output.parent.resolve())
        )
    )
    try:
        raw_root = stage / "raw"
        raw_root.mkdir()
        fud_records = fetch_fud(raw_root, args.asahi_installer / "src")
        base_records = collect_base_system(raw_root, args.base_system)
        copy_file(args.kernelcache, raw_root / "kernelcache.release.mac16j.im4p")

        outputs = collect_vendorfw(
            raw_root, raw_root / "kernelcache.release.mac16j.im4p",
            args.asahi_installer / "src"
        )
        for name, data in sorted(outputs.items()):
            copy_bytes(stage / "vendorfw" / name, data)

        archive = stage / "j614s-25F84-raw-firmware.tar.gz"
        normalized_tar(raw_root, archive)
        provenance = {
            "scope": "Mac16,8 / J614s board-paired firmware slice",
            "product_version": "26.5.2",
            "product_build": "25F84",
            "device_class": DEVICE_CLASS,
            "ipsw_url": IPSW_URL,
            "ipsw_size": IPSW_SIZE,
            "build_manifest_sha256": BUILD_MANIFEST_SHA256,
            "asahi_installer_commit": asahi_commit,
            "source_hashes": source_hashes,
            "fud": fud_records,
            "base_system": base_records,
            "vendorfw_file_count": len(outputs),
            "raw_archive": {
                "path": archive.name,
                "size": archive.stat().st_size,
                "sha256": sha256_file(archive),
                "mode": "0444",
            },
            "limitations": [
                "ALS calibration is machine-private and is not present; collect it "
                "from the J614s macOS ioreg/FactoryData before enabling AOP ALS.",
                "AMKOR Bluetooth and WiFi .pcfb/.man inputs are preserved raw, but "
                "current asahi_firmware has no Linux output naming for them.",
                "iBoot-loaded RTKit firmware is intentionally excluded, matching "
                "the upstream all_firmware collection contract.",
            ],
        }
        provenance_path = stage / "provenance.json"
        copy_bytes(
            provenance_path,
            (json.dumps(provenance, indent=2, sort_keys=True) + "\n").encode(),
        )
        inventory = inventory_files(stage, excluded={"SHA256SUMS"})
        sums = "".join(
            f"{record['sha256']}  {record['path']}\n" for record in inventory
        )
        copy_bytes(stage / "SHA256SUMS", sums.encode())
        os.replace(stage, args.output)
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise

    result = {
        "output": str(args.output),
        "vendorfw_files": len(outputs),
        "raw_fud_files": len(fud_records),
        "raw_archive_sha256": sha256_file(
            args.output / "j614s-25F84-raw-firmware.tar.gz"
        ),
        "sha256sums_sha256": sha256_file(args.output / "SHA256SUMS"),
        "als": "absent: requires capture from the J614s macOS installation",
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
