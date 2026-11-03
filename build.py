#!/usr/bin/env python3
"""Build locally using an exact, user-supplied vendor driver. No downloads."""
import argparse
import hashlib
from pathlib import Path
import struct
import zipfile

ORIGINAL_SHA256 = "7c819c0f62642272466673e337e8bba64b95a624bcd8dbd62895666cf1a14f5d"
PATCHED_SHA256 = "ce569057afb29cd691c84391f2d278d3e2dc235e851104d193ef69d0ff8f5335"
PATCHES = (
    (0x40BB2C, 0x54000261, 0x14000013),
    (0x40F660, 0x54000141, 0x1400000A),
)
FILES = ("module.prop", "customize.sh", "service.sh", "action.sh", "uninstall.sh", "skip_mount")


def patch_driver(original):
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA256:
        raise ValueError("Unsupported original driver SHA-256; refusing to patch")
    patched = bytearray(original)
    for offset, expected, replacement in PATCHES:
        if struct.unpack_from("<I", original, offset)[0] != expected:
            raise ValueError("Instruction mismatch; refusing to patch")
        struct.pack_into("<I", patched, offset, replacement)
    if hashlib.sha256(patched).hexdigest() != PATCHED_SHA256:
        raise ValueError("Unexpected patched driver SHA-256")
    return bytes(patched)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("driver", type=Path, help="Original qca_cld3_peach_v2.ko from your device")
    parser.add_argument("--output", type=Path, default=Path("build/K80Pro-6GHz-Magisk-v1.3-local.zip"))
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; choose another path")
    templates = Path(__file__).resolve().parent / "module"
    try:
        patched = patch_driver(args.driver.read_bytes())
        contents = {name: (templates / name).read_bytes() for name in FILES}
        contents["driver.ko"] = patched
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in contents.items():
                info = zipfile.ZipInfo(name, date_time=(2026, 11, 1, 0, 0, 0))
                info.create_system = 3
                mode = 0o100755 if name.endswith(".sh") else 0o100644
                info.external_attr = mode << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data)
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + "\n")
    print("Built local module; patched driver SHA-256: " + PATCHED_SHA256)
    print("Contains a vendor-derived binary: review NOTICE before redistribution.")


if __name__ == "__main__":
    main()
