#!/usr/bin/env python3
"""Host-only USB-root gate tests: synthetic regular files and fake sysfs.

No block-device node, mount, loop, fsck, USB or rig access. C is compiled for
the host; this is not an arm64/static build or an initramfs qualification.
"""
import binascii
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import struct
import subprocess
import tempfile
import uuid

REPO = Path(__file__).resolve().parent.parent
DISK = "192409a8-fe11-4cbf-9182-14eb737b69a6"
PART = "e4731abe-3566-4c3a-8019-c8828ca27a5a"
FS = "912d5c4e-7475-4875-a178-52ce5119a703"
TYPE = "0fc63daf-8483-4772-8e79-3d69d8477de4"
SIZE = 8 * 1024 * 1024
SECTORS = SIZE // 512


def header(current, alternate, table, entries, disk_id=DISK):
    h = bytearray(512)
    struct.pack_into("<8sIIIIQQQQ16sQIII", h, 0, b"EFI PART", 0x10000, 92, 0, 0,
                     current, alternate, 34, SECTORS - 34, uuid.UUID(disk_id).bytes_le,
                     table, 128, 128, binascii.crc32(entries))
    struct.pack_into("<I", h, 16, binascii.crc32(h[:92]))
    return h


def fixture(path, *, extra=False, state=1, recovery=False, wrong_type=False,
            fs_uuid=FS, ext4_blocks=None, backup_difference=False, extent=2048):
    """Minimal valid metadata, not a complete ext4 filesystem."""
    array = bytearray(128 * 128)
    array[:16] = uuid.UUID(TYPE if not wrong_type else DISK).bytes_le
    array[16:32] = uuid.UUID(PART).bytes_le
    struct.pack_into("<QQQ", array, 32, extent, SECTORS - 34, 0)
    array[56:56 + 18] = "t6040root".encode("utf-16le")
    if extra:
        array[128:144] = uuid.UUID(TYPE).bytes_le
    backup = bytearray(array)
    if backup_difference:
        backup[56] = ord("x")
    sb = bytearray(1024)
    blocks = ext4_blocks if ext4_blocks is not None else ((SECTORS - 34 - extent + 1) * 512) // 4096
    struct.pack_into("<I", sb, 4, blocks)
    struct.pack_into("<I", sb, 24, 2)
    struct.pack_into("<HH", sb, 56, 0xef53, state)
    struct.pack_into("<I", sb, 76, 1)
    struct.pack_into("<I", sb, 96, 4 if recovery else 0)
    sb[104:120] = uuid.UUID(fs_uuid).bytes
    sb[120:129] = b"t6040root"
    mbr = bytearray(512)
    mbr[450] = 0xee
    struct.pack_into("<II", mbr, 454, 1, SECTORS - 1)
    mbr[510:512] = b"\x55\xaa"
    with path.open("wb") as f:
        f.truncate(SIZE)
        for offset, data in [(0, mbr), (512, header(1, SECTORS - 1, 2, array)),
                             (1024, array), ((SECTORS - 33) * 512, backup),
                             ((SECTORS - 1) * 512, header(SECTORS - 1, 1, SECTORS - 33, backup)),
                             (extent * 512 + 1024, sb)]:
            f.seek(offset)
            f.write(data)


def main():
    results = []
    with tempfile.TemporaryDirectory(prefix="usb-root-6005-", dir=os.environ.get("T6040_TEST_TMP", REPO / ".tmp")) as td:
        tmp = Path(td).resolve()
        binary = tmp / "metadata"
        supplied = os.environ.get("METADATA_BINARY")
        if supplied:
            binary = Path(supplied).resolve(strict=True)
        else:
            subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                            *shlex.split(os.environ.get("CFLAGS", "")),
                            str(REPO / "scripts/t6040-usb-root-metadata.c"), "-o", str(binary)], check=True)
        image = tmp / "root.img"
        options = ["--disk-guid", DISK, "--partuuid", PART, "--fsuuid", FS,
                   "--media-bytes", str(SIZE), "--layout-bytes", str(SIZE)]

        def check(name, argv, ok, why=None):
            p = subprocess.run([str(x) for x in argv], capture_output=True, text=True)
            assert (p.returncode == 0) == ok, (name, p.returncode, p.stdout, p.stderr)
            if why:
                assert why in p.stderr, (name, p.stderr, why)
            if not ok:
                assert "metadata_gate=PASS" not in p.stdout, (name, p.stdout)
            results.append({"case": name, "verdict": "PASS", "exit": p.returncode,
                            "reason": p.stderr.strip(), "output": p.stdout.strip()})
            return p

        def meta(name, ok, why=None, **kw):
            fixture(image, **kw)
            before = hashlib.sha256(image.read_bytes()).hexdigest()
            p = check(name, [binary, "--image", image, *options], ok, why)
            assert hashlib.sha256(image.read_bytes()).hexdigest() == before, name
            return p

        meta("clean GPT/ext4 metadata", True)
        meta("ext4 dirty", False, "dirty", state=0)
        meta("ext4 error bit", False, "dirty", state=3)
        meta("journal replay pending", False, "journal replay", recovery=True)
        meta("filesystem UUID mismatch", False, "UUID mismatch", fs_uuid=DISK)
        meta("non-Linux partition type", False, "partition type", wrong_type=True)
        meta("extra partition", False, "additional GPT partition", extra=True)
        meta("backup disagrees but valid CRC", False, "GPT copies", backup_difference=True)
        meta("partition extent changed", False, "root extent", extent=4096)
        meta("filesystem overflows partition", False, "size exceeds", ext4_blocks=SIZE)
        fixture(image)
        for name, offset, why in [("primary header CRC", 512 + 48, "header CRC"),
                                  ("primary partition CRC", 1024 + 72, "array CRC"),
                                  ("backup header CRC", SIZE - 512 + 48, "header CRC"),
                                  ("backup partition CRC", SIZE - 33 * 512 + 72, "array CRC"),
                                  ("hybrid MBR", 462 + 4, "protective MBR")]:
            fixture(image)
            with image.open("r+b") as f:
                f.seek(offset)
                original = f.read(1)[0]
                f.seek(offset)
                f.write(bytes([original ^ 1]))
            check(name, [binary, "--image", image, *options], False, why)
        fixture(image)
        check("wrong pinned disk GUID", [binary, "--image", image, *options, "--disk-guid", PART], False, "repeated option")
        bad_options = options.copy()
        bad_options[1] = PART
        check("disk GUID differs", [binary, "--image", image, *bad_options], False, "disk GUID")
        bad_options = options.copy()
        bad_options[3] = DISK
        check("partition GUID differs", [binary, "--image", image, *bad_options], False, "PARTUUID")
        check("capacity mismatch", [binary, "--image", image, *options[:-4], "--media-bytes", str(SIZE + 512), "--layout-bytes", str(SIZE)], False, "capacity")
        alias = tmp / "alias"
        alias.symlink_to(image)
        check("symlink rejected", [binary, "--image", alias, *options], False, "wrong type")
        check("directory rejected", [binary, "--image", tmp, *options], False, "wrong type")
        check("regular file cannot use disk mode", [binary, "--disk", image, *options], False, "wrong type")
        with image.open("r+b") as f:
            f.truncate(SIZE - 1)
        check("truncated media", [binary, "--image", image, *options], False, "capacity")
        fixture(image)

        # Applet adapter: actual production shell functions and C binary run
        # unchanged against a fake sysfs hierarchy. Only readlink -f needs a
        # portable host implementation on macOS.
        bb = tmp / "bb"
        bb.write_text("#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\n"
                      "a=sys.argv[1:]\n"
                      "if a[:2]==['readlink','-f']:\n"
                      " try: print(Path(a[2]).resolve(strict=True))\n"
                      " except OSError: sys.exit(1)\n"
                      "else: os.execvp(a[0],a)\n")
        bb.chmod(0o755)
        sys = tmp / "sys"
        dev = tmp / "dev"
        (sys / "class/block").mkdir(parents=True)
        dev.mkdir()
        (tmp / "proc").mkdir()
        (tmp / "proc/self").mkdir()
        mounts = tmp / "proc/self/mountinfo"
        mounts.write_text("")
        cmdline = tmp / "proc/cmdline"
        cmdline.write_text(f"maxcpus=1 root=PARTUUID={PART} rootfstype=ext4\n")
        identity = tmp / "identity"
        identity_text = ("format=t6040-usb-root-identity-v1\n" +
                         f"disk_guid={DISK}\npartuuid={PART}\nfsuuid={FS}\nmedia_bytes={SIZE}\nlayout_bytes={SIZE}\n" +
                         "usb_vendor=1234\nusb_product=5678\nusb_serial=fixture-stick\nusb_route=1\nusb_controller=392280000.usb\nremovable=1\n")
        identity.write_text(identity_text)

        def device(name, *, controller="392280000.usb", serial="fixture-stick", removable="1", vendor="1234", route="1"):
            parent = sys / "devices/platform/soc" / controller / ("usb3/3-" + name)
            parent.mkdir(parents=True)
            for k, v in {"idVendor": vendor, "idProduct": "5678", "serial": serial, "devpath": route}.items():
                (parent / k).write_text(v + "\n")
            block = parent / "host0/target0:0:0/0:0:0:0/block" / name
            block.mkdir(parents=True)
            (block / "removable").write_text(removable + "\n")
            (block / "size").write_text(str(SIZE // 512) + "\n")
            minor = (ord(name[-1]) - ord('a')) * 16
            (block / "dev").write_text(f"8:{minor}\n")
            (block / (name + "1")).mkdir()
            (block / (name + "1") / "partition").write_text("1\n")
            (block / (name + "1") / "dev").write_text(f"8:{minor + 1}\n")
            (block / (name + "1") / "start").write_text("2048\n")
            (block / (name + "1") / "size").write_text(str(SECTORS - 34 - 2048 + 1) + "\n")
            (sys / "class/block" / name).symlink_to(block)
            (sys / "class/block" / (name + "1")).symlink_to(block / (name + "1"))
            shutil.copyfile(image, dev / name)
            (dev / (name + "1")).touch()
            return parent, block

        env = os.environ.copy()
        env["USBROOT_BB"] = str(bb)
        wrapper = tmp / "select"
        wrapper.write_text('#!/bin/sh\n. "$1"\nshift\nusb_root_select "$@"\n')
        wrapper.chmod(0o755)
        selector = [wrapper, REPO / "scripts/t6040-usb-root-select.sh", sys, dev, identity, binary, "image"]

        def select(name, ok, why=None):
            p = subprocess.run([str(x) for x in selector], env=env, capture_output=True, text=True)
            assert (p.returncode == 0) == ok, (name, p.stdout, p.stderr)
            if why:
                assert why in p.stderr, (name, p.stderr)
            if not ok:
                assert "usb_root_device=" not in p.stdout, (name, p.stdout)
            results.append({"case": name, "verdict": "PASS", "exit": p.returncode,
                            "reason": p.stderr.strip(), "output": p.stdout.strip()})
            return p

        select("no stick", False, "found 0")
        parent, block = device("sdb")
        assert f"usb_root_device={dev}/sdb1" in select("valid right-port stick independent of sd order", True).stdout
        (parent / "serial").write_text("other-stick\n")
        select("wrong stick serial", False, "found 0")
        (parent / "serial").write_text("fixture-stick\n")
        (parent / "idVendor").write_text("ffff\n")
        select("wrong USB vendor", False, "found 0")
        (parent / "idVendor").write_text("1234\n")
        (parent / "devpath").write_text("1.2\n")
        select("extra hub route", False, "found 0")
        (parent / "devpath").write_text("1\n")
        (block / "removable").write_text("0\n")
        select("non-removable device", False, "found 0")
        (block / "removable").write_text("1\n")
        (block / "size").write_text("1\n")
        select("sysfs capacity mismatch before metadata", False, "found 0")
        (block / "size").write_text(str(SIZE // 512) + "\n")
        mounts.write_text("1 0 8:17 / /other rw - ext4 /dev/sdb1 rw\n")
        select("already mounted partition", False, "already mounted")
        mounts.write_text("1 0 8:16 / /other rw - ext4 /dev/sdb rw\n")
        select("already mounted whole disk", False, "already mounted")
        mounts.write_text("")
        (block / "sdb1/start").write_text("4096\n")
        select("stale kernel partition start", False, "kernel partition extent")
        (block / "sdb1/start").write_text("2048\n")
        (block / "sdb1/size").write_text("1\n")
        select("stale kernel partition size", False, "kernel partition extent")
        (block / "sdb1/size").write_text(str(SECTORS - 34 - 2048 + 1) + "\n")
        second, second_block = device("sda")
        select("ambiguous duplicate USB identity", False, "found 2")
        (second / "serial").write_text("different\n")
        select("unrelated second stick ignored", True)
        for token in [f"root=/dev/sdb1", "root=LABEL=t6040root", f"root=PARTUUID={DISK}",
                      f"root=PARTUUID={PART} root=PARTUUID={PART}", ""]:
            cmdline.write_text(token + "\n")
            select("reject root selector " + (token or "absent"), False)
        cmdline.write_text(f"root=PARTUUID={PART} rootfstype=ext4\n")
        identity.write_text(identity_text + "usb_serial=duplicate\n")
        select("duplicate identity field", False, "duplicate")
        identity.write_text(identity_text + "unexpected=1\n")
        select("unknown identity field", False, "unknown")
        identity.write_text(identity_text.replace("usb_serial=fixture-stick", "usb_serial="))
        select("unpinned serial", False, "empty")
        identity.write_text(identity_text)
        # Valid GUIDs on the wrong physical controller must never reach reads.
        (sys / "class/block/sdb").unlink()
        wrong_parent, wrong_block = device("sdc", controller="382280000.usb")
        select("left-port stick rejected", False, "found 0")
        (sys / "class/block/sdb").symlink_to(block)
        # An internal NVMe or SD disk is never a candidate, even if a caller
        # placed an exact copy of the root image at its fixture device node.
        (sys / "class/block/sdb").unlink()
        device("nvme0n1")
        device("mmcblk0")
        select("matching metadata on NVMe and SD is never selected", False, "found 0")
        (sys / "class/block/sdb").symlink_to(block)
        fixture(dev / "sdb", state=0)
        select("dirty matching USB root rejected before mount", False, "dirty")
        fixture(dev / "sdb")
        (sys / "class/block/sdb1").unlink()
        (sys / "class/block/sdb1").symlink_to(second_block / "sda1")
        select("partition symlink points at different disk", False, "found 0")

        out = Path(os.environ.get("T6040_TEST_RESULTS", REPO / "evidence/2026-10-24-usb-root-gates-tests.json"))
        out.write_text(json.dumps({"scope": "native helper + regular synthetic metadata images + fake sysfs only; no fsck/kernel/initramfs/rig result",
                                   "platform": os.uname().sysname + " " + os.uname().machine,
                                   "metadata_binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                                   "compiler_flags": os.environ.get("CFLAGS", "") if not supplied else "supplied binary",
                                   "cases": results, "passed": len(results)}, indent=2) + "\n")
        print(f"USB-root gates: {len(results)} cases PASS; evidence {out}")


if __name__ == "__main__":
    main()
