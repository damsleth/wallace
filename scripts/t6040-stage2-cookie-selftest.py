#!/usr/bin/env python3
"""Host model tests for the m1n1/U-Boot one-shot proxy-cookie contract."""

import struct
import zlib


PAGE_SIZE = 0x4000
MAGIC = 0x3130305958504C57
VERSION = 1
REASON_NO_MEDIA = 1
COOKIE = struct.Struct("<QIIIIII")


def make_cookie() -> bytearray:
    page = bytearray(PAGE_SIZE)
    prefix = struct.pack("<QIIIII", MAGIC, VERSION, COOKIE.size, REASON_NO_MEDIA, 0, 0)
    crc = zlib.crc32(prefix)
    page[: COOKIE.size] = COOKIE.pack(
        MAGIC, VERSION, COOKIE.size, REASON_NO_MEDIA, 0, 0, crc
    )
    return page


def take_cookie(page: bytearray) -> bool:
    saved = bytes(page[: COOKIE.size])
    page[:] = bytes(PAGE_SIZE)  # clear before validation, including malformed input
    magic, version, size, reason, reserved0, reserved1, crc = COOKIE.unpack(saved)
    return (
        magic == MAGIC
        and version == VERSION
        and size == COOKIE.size
        and reason == REASON_NO_MEDIA
        and reserved0 == 0
        and reserved1 == 0
        and crc == zlib.crc32(saved[:-4])
    )


def main() -> None:
    cold = bytearray(PAGE_SIZE)
    assert not take_cookie(cold) and not any(cold)

    valid = make_cookie()
    assert take_cookie(valid) and not any(valid)

    corrupt = make_cookie()
    corrupt[8] ^= 1
    assert not take_cookie(corrupt) and not any(corrupt)

    replay = valid
    assert not take_cookie(replay) and not any(replay)

    print("PASS cold/default, valid, corrupt, clear-before-use, and replay cases")


if __name__ == "__main__":
    main()
