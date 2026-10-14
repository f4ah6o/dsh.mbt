#!/usr/bin/env python3
"""Build the bounded envelope carried in the release CLI's Mach-O section."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import stat
import struct
import zipfile

MAGIC = b"DSH-MACOS-APP\0\0\0"
LIMIT = 512 * 1024 * 1024

def prepare(archive, version, output):
    if not re.fullmatch(r"[0-9][0-9.\-]{0,31}", version):
        raise ValueError("invalid bundle version")
    if not 0 < archive.stat().st_size <= LIMIT:
        raise ValueError("app archive exceeds its size limit")
    data = archive.read_bytes()
    with zipfile.ZipFile(archive) as z:
        entries = z.infolist()
        if not 0 < len(entries) <= 4096 or sum(i.file_size for i in entries) > 1024**3:
            raise ValueError("app archive exceeds its entry/expanded size limits")
        names = set()
        manifest = []
        for i in entries:
            name = i.filename.rstrip("/")
            if (not name or any(c < " " or c > "~" or c in "\\:" for c in name)
                or any(p in ("", ".", "..") or len(p) > 255 for p in name.split("/"))
                or name.casefold() in names
                or not (name == "Dsh-macos-arm64" or name.startswith("Dsh-macos-arm64/")
                        or name == "__MACOSX" or name.startswith("__MACOSX/"))):
                raise ValueError("unsafe/aliased archive entry")
            names.add(name.casefold())
            mode = i.external_attr >> 16
            if stat.S_IFMT(mode) not in (stat.S_IFREG, stat.S_IFDIR) or mode & 0o6002 or (stat.S_ISREG(mode) and mode & 0o20):
                raise ValueError("archive entries must be non-writable regular files/directories")
            if i.file_size > 256 * 1024**2 or i.compress_type not in (0, 8) or i.flag_bits & ~0x808:
                raise ValueError("unsupported archive encoding")
            if not name.startswith("__MACOSX"):
                content = b"" if i.is_dir() else z.read(i)
                encoded_name = name.encode("ascii")
                manifest.append((encoded_name, struct.pack("<IIQ32s", len(encoded_name), mode,
                    0 if i.is_dir() else len(content), bytes(32) if i.is_dir() else hashlib.sha256(content).digest()) + encoded_name))
        app = "Dsh-macos-arm64/Dsh.app/Contents/"
        info = plistlib.loads(z.read(app + "Info.plist"))
        if (info.get("CFBundleIdentifier") != "org.fu2hito.dsh"
            or info.get("CFBundleExecutable") != "dsh-desktop"
            or info.get("CFBundleShortVersionString") != version
            or info.get("CFBundleVersion") != version):
            raise ValueError("bundle identity/version does not match the CLI source")
        for name in ("MacOS/dsh-desktop", "Helpers/dsh", "Frameworks/libgpui_macos.dylib", "_CodeSignature/CodeResources"):
            z.getinfo(app + name)
        if app + "Resources/GPUI_TESTING" in z.namelist():
            raise ValueError("refusing a testing bundle")
        helper = z.read(app + "Helpers/dsh")
        # Helpers remain the original unbundled CLI; embedding the outer CLI
        # recursively would duplicate the app and its launch resource.
        if len(helper) < 32 or struct.unpack_from("<II", helper) != (0xfeedfacf, 0x100000c):
            raise ValueError("the app helper must be an arm64 Mach-O executable")
        ncmds, sizecmds = struct.unpack_from("<II", helper, 16)
        if ncmds > 512 or sizecmds > len(helper) - 32:
            raise ValueError("invalid helper Mach-O load commands")
        pos = 32
        for _ in range(ncmds):
            if pos + 8 > 32 + sizecmds:
                raise ValueError("invalid helper Mach-O load commands")
            cmd, size = struct.unpack_from("<II", helper, pos)
            if size < 8 or size % 8 or pos + size > 32 + sizecmds:
                raise ValueError("invalid helper Mach-O load commands")
            if cmd == 0x19 and size >= 72 and helper[pos+8:pos+24].rstrip(b"\0") == b"__DSH":
                raise ValueError("the app's private CLI helper must be unbundled")
            pos += size
        if pos != 32 + sizecmds:
            raise ValueError("invalid helper Mach-O load commands")
        bad = z.testzip()
        if bad:
            raise ValueError("corrupt app archive member: " + bad)
    digest = hashlib.sha256(data).digest()
    encoded = version.encode("ascii")
    manifest_bytes = struct.pack("<I", len(manifest)) + b"".join(record for _, record in sorted(manifest))
    output.write_bytes(struct.pack("<16sIIQ32sII", MAGIC, 2, len(encoded), len(data), digest, len(manifest_bytes), 0) + encoded + manifest_bytes + data)
    return {"version": version, "archive_size": len(data), "archive_sha256": digest.hex(), "payload_size": output.stat().st_size}

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--archive", type=Path, required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    print(json.dumps(prepare(a.archive, a.version, a.output), sort_keys=True))
