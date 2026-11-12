#!/usr/bin/env python3
"""Choose which Lampa players the app announces itself as.

tvOS reads an app's URL schemes from its Info.plist when the app is installed, so the app
cannot change them while running. This script rewrites them inside the .ipa instead, in
seconds, on any OS (no Mac, no rebuild). Upload the result to atvloadly.

  python set_schemes.py AetherPlayer.ipa AetherPlayer_senplayer.ipa senplayer
  python set_schemes.py AetherPlayer.ipa out.ipa senplayer vlc svplayer

Names (Lampa Apple TV player -> URL scheme Lampa opens):
  vlc        vlc-x-callback
  infuse     infuse
  senplayer  senplayer
  vidhub     open-vidhub
  svplayer   svplayer
Any other word is used as a raw scheme. "inner" is Lampa's built-in web player; it has no URL
scheme, so it cannot be claimed this way.

Claim only players whose real app is NOT installed on the Apple TV. If two apps answer the
same scheme, tvOS picks one of them and you cannot choose.
"""
import plistlib
import re
import sys
import zipfile

ALIASES = {
    "vlc": "vlc-x-callback",
    "infuse": "infuse",
    "senplayer": "senplayer",
    "vidhub": "open-vidhub",
    "svplayer": "svplayer",
}


def resolve(names):
    schemes = ["aetherplayer"]  # always kept: our own link form
    for name in names:
        n = name.strip().lower()
        if n == "inner":
            sys.exit("'inner' is Lampa's built-in player and has no URL scheme; it cannot be claimed.")
        scheme = ALIASES.get(n, n)
        if scheme not in schemes:
            schemes.append(scheme)
    return schemes


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    src, dst, names = argv[1], argv[2], argv[3:]
    if src == dst:
        sys.exit("Write to a different file than the input.")
    schemes = resolve(names)

    with zipfile.ZipFile(src) as zi:
        keys = [n for n in zi.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(keys) != 1:
            sys.exit(f"Expected exactly one app Info.plist in the IPA, found {len(keys)}.")
        key = keys[0]
        raw = zi.read(key)
        plist = plistlib.loads(raw)

        types = plist.get("CFBundleURLTypes") or [
            {"CFBundleURLName": plist.get("CFBundleIdentifier", "app")}
        ]
        types[0]["CFBundleURLSchemes"] = schemes
        plist["CFBundleURLTypes"] = types[:1]

        fmt = plistlib.FMT_BINARY if raw[:6] == b"bplist" else plistlib.FMT_XML
        new = plistlib.dumps(plist, fmt=fmt)

        with zipfile.ZipFile(dst, "w") as zo:
            for info in zi.infolist():
                data = new if info.filename == key else zi.read(info.filename)
                zo.writestr(info, data, compress_type=info.compress_type)

    print(f"{dst}: answers to {', '.join(s + '://' for s in schemes)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
