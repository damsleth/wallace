#!/usr/bin/env python3
"""Write a deterministic SVR4 newc archive for a directory tree."""

import os
import stat
import sys
from pathlib import Path


def pad4(stream, size):
    padding = (-size) & 3
    if padding:
        stream.write(b"\0" * padding)


def write_entry(stream, inode, name, mode, nlink, data=b"", rdev=0):
    encoded_name = os.fsencode(name) + b"\0"
    fields = (
        inode,
        mode,
        0,  # uid
        0,  # gid
        nlink,
        0,  # mtime
        len(data),
        0,  # devmajor
        0,  # devminor
        os.major(rdev) if rdev else 0,
        os.minor(rdev) if rdev else 0,
        len(encoded_name),
        0,  # check
    )
    header = b"070701" + b"".join(f"{value:08x}".encode() for value in fields)
    if len(header) != 110:
        raise AssertionError(f"newc header is {len(header)} bytes, expected 110")
    stream.write(header)
    stream.write(encoded_name)
    pad4(stream, len(header) + len(encoded_name))
    stream.write(data)
    pad4(stream, len(data))


def archive_paths(root):
    yield Path(".")
    yield from sorted(
        (path.relative_to(root) for path in root.rglob("*")),
        key=lambda path: os.fsencode(path.as_posix()),
    )


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} ROOT")
    root = Path(sys.argv[1])
    if not root.is_dir():
        raise SystemExit(f"not a directory: {root}")

    stream = sys.stdout.buffer
    inode = 1
    for relative in archive_paths(root):
        path = root if relative == Path(".") else root / relative
        metadata = path.lstat()
        mode = metadata.st_mode
        rdev = metadata.st_rdev if stat.S_ISCHR(mode) or stat.S_ISBLK(mode) else 0
        if stat.S_ISREG(mode):
            data = path.read_bytes()
            nlink = 1
        elif stat.S_ISLNK(mode):
            data = os.fsencode(os.readlink(path))
            nlink = 1
        elif stat.S_ISDIR(mode):
            data = b""
            nlink = 2
        elif stat.S_ISCHR(mode) or stat.S_ISBLK(mode) or stat.S_ISFIFO(mode):
            data = b""
            nlink = 1
        else:
            raise RuntimeError(f"unsupported file type in initramfs: {path}")
        name = "." if relative == Path(".") else f"./{relative.as_posix()}"
        write_entry(stream, inode, name, mode, nlink, data, rdev)
        inode += 1

    write_entry(stream, inode, "TRAILER!!!", 0, 1)


if __name__ == "__main__":
    main()
