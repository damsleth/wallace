#!/usr/bin/env python3
"""Extract the J614s ALS firmware bundle from read-only macOS captures."""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import shutil
import sys
import tempfile
from pathlib import Path
from typing import NoReturn

EXPECTED_MODEL = "Mac16,8"


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ioreg-plist", required=True, type=Path)
    parser.add_argument("--factory-dir", required=True, type=Path)
    parser.add_argument("--model-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def require_plain_file(path: Path, label: str) -> None:
    if path.is_symlink() or not path.is_file():
        fail(f"{label} is not a regular non-symlink file: {path}")
    if path.stat().st_size == 0:
        fail(f"{label} is empty: {path}")


def main() -> int:
    os.umask(0o077)
    args = parse_args()

    require_plain_file(args.model_file, "model capture")
    require_plain_file(args.ioreg_plist, "IORegistry capture")
    if args.factory_dir.is_symlink() or not args.factory_dir.is_dir():
        fail(f"FactoryData capture is not a regular directory: {args.factory_dir}")
    capture_root = args.model_file.parent.resolve()
    if (
        args.ioreg_plist.parent.resolve() != capture_root
        or args.factory_dir.parent.resolve() != capture_root
    ):
        fail("model, IORegistry, and FactoryData inputs do not share one capture root")

    model = args.model_file.read_text(encoding="utf-8").strip()
    if model != EXPECTED_MODEL:
        fail(f"source model is {model!r}, expected {EXPECTED_MODEL!r}")
    if args.output.exists():
        fail(f"output already exists: {args.output}")

    with args.ioreg_plist.open("rb") as stream:
        tree = plistlib.load(stream)
    try:
        node = tree[0]
        for _ in range(3):
            node = node["IORegistryEntryChildren"][0]
        calibration = node["CalibrationData"]
    except (IndexError, KeyError, TypeError) as error:
        fail(f"upstream ALS CalibrationData path is absent: {error}")
    if not isinstance(calibration, bytes) or not calibration:
        fail("CalibrationData is not a non-empty byte string")

    factory_files = sorted(
        path
        for path in args.factory_dir.iterdir()
        if path.name.startswith("HmCA")
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size > 0
    )
    if not factory_files:
        fail("no non-empty regular HmCA* FactoryData files were captured")

    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    stage = Path(
        tempfile.mkdtemp(
            prefix=f".{args.output.name}.tmp-",
            dir=args.output.parent,
        )
    )
    try:
        apple = stage / "apple"
        apple.mkdir(mode=0o700)
        calibration_path = apple / "aop-als-cal.bin"
        calibration_path.write_bytes(calibration)
        calibration_path.chmod(0o600)
        for source in factory_files:
            destination = apple / source.name
            shutil.copyfile(source, destination)
            destination.chmod(0o600)

        outputs = sorted(path for path in apple.iterdir() if path.is_file())
        manifest = "".join(
            f"{sha256(path)}  apple/{path.name}\n" for path in outputs
        )
        manifest_path = stage / "SHA256SUMS"
        model_path = stage / "SOURCE_MODEL"
        manifest_path.write_text(manifest, encoding="ascii")
        model_path.write_text(f"{model}\n", encoding="ascii")
        manifest_path.chmod(0o600)
        model_path.chmod(0o600)

        if args.output.exists():
            fail(f"output appeared during extraction: {args.output}")
        stage.rename(args.output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)

    print(f"source model: {model}")
    print(f"CalibrationData bytes: {len(calibration)}")
    print(f"HmCA files: {len(factory_files)}")
    print(manifest, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
