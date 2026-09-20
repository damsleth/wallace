#!/usr/bin/env python3
"""Build the deterministic, single-board FIT loaded from the SD FAT partition."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def run(*command: str, env=None) -> None:
    subprocess.run(command, check=True, env=env)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--dtb", required=True, type=Path)
    parser.add_argument("--initramfs", required=True, type=Path)
    parser.add_argument("--bootargs", required=True)
    parser.add_argument("--mkimage", required=True, type=Path)
    parser.add_argument("--fdtput", default="fdtput")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--source-date-epoch", required=True, type=int)
    args = parser.parse_args()

    for path in (args.kernel, args.dtb, args.initramfs, args.mkimage):
        if not path.is_file():
            raise SystemExit(f"missing input: {path}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["SOURCE_DATE_EPOCH"] = str(args.source_date_epoch)

    with tempfile.TemporaryDirectory(prefix="wallace-fit.") as directory:
        work = Path(directory)
        kernel = work / "Image"
        dtb = work / "j614s.dtb"
        initramfs = work / "initramfs.cpio.gz"
        shutil.copyfile(args.kernel, kernel)
        shutil.copyfile(args.dtb, dtb)
        shutil.copyfile(args.initramfs, initramfs)

        # The DT carried by the FIT is the single source of truth for Linux's
        # command line. It remains hash-covered by the FIT and its manifest.
        run(args.fdtput, "-c", str(dtb), "/chosen")
        run(args.fdtput, "-t", "s", str(dtb), "/chosen", "bootargs", args.bootargs)

        its = work / "wallace.its"
        its.write_text(
            "/dts-v1/;\n\n"
            "/ {\n"
            "    description = \"Wallace T6040 J614s SD daily bundle\";\n"
            "    #address-cells = <2>;\n"
            "    images {\n"
            "        kernel {\n"
            "            description = \"Linux arm64 Image\";\n"
            "            data = /incbin/(\"Image\");\n"
            "            type = \"kernel_noload\";\n"
            "            arch = \"arm64\";\n"
            "            os = \"linux\";\n"
            "            compression = \"none\";\n"
            "            load = <0x0 0x0>;\n"
            "            entry = <0x0 0x0>;\n"
            "            hash-1 { algo = \"sha256\"; };\n"
            "        };\n"
            "        fdt {\n"
            "            description = \"Apple J614s daily DTB\";\n"
            "            data = /incbin/(\"j614s.dtb\");\n"
            "            type = \"flat_dt\";\n"
            "            arch = \"arm64\";\n"
            "            compression = \"none\";\n"
            "            hash-1 { algo = \"sha256\"; };\n"
            "        };\n"
            "        ramdisk {\n"
            "            description = \"Wallace SD-root initramfs\";\n"
            "            data = /incbin/(\"initramfs.cpio.gz\");\n"
            "            type = \"ramdisk\";\n"
            "            arch = \"arm64\";\n"
            "            os = \"linux\";\n"
            "            compression = \"none\";\n"
            "            hash-1 { algo = \"sha256\"; };\n"
            "        };\n"
            "    };\n"
            "    configurations {\n"
            "        default = \"conf-j614s\";\n"
            "        conf-j614s {\n"
            "            description = \"MacBook Pro 14-inch M4 Pro (J614s)\";\n"
            "            kernel = \"kernel\";\n"
            "            fdt = \"fdt\";\n"
            "            ramdisk = \"ramdisk\";\n"
            "        };\n"
            "    };\n"
            "};\n",
            encoding="utf-8",
        )
        fit = work / "wallace.itb"
        run(str(args.mkimage), "-f", str(its), str(fit), env=env)
        shutil.copyfile(fit, args.output)

        manifest = {
            "schema": 1,
            "kind": "t6040-j614s-sd-linux-fit",
            "source_date_epoch": args.source_date_epoch,
            "configuration": "conf-j614s",
            "bootargs": args.bootargs,
            "components": {
                "kernel": {"size": kernel.stat().st_size, "sha256": sha256(kernel)},
                "dtb_with_bootargs": {"size": dtb.stat().st_size, "sha256": sha256(dtb)},
                "initramfs": {
                    "size": initramfs.stat().st_size,
                    "sha256": sha256(initramfs),
                },
            },
            "fit": {"size": fit.stat().st_size, "sha256": sha256(fit)},
        }
        args.manifest.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
