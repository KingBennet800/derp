#!/usr/bin/env python3
"""Derp's app source for SideStore, AltStore and LiveContainer (they all read
AltStore's source format). Each release publishes it next to Derp.ipa, so
adding this one link keeps Derp up to date in any of them:

    https://github.com/KingBennet800/derp/releases/latest/download/derp-source.json

    python3 ios/source.py VERSION Derp.ipa derp-source.json
"""
import datetime
import json
import os
import sys

REPO = "https://github.com/KingBennet800/derp"
ABOUT = (
    "Derp is a calm, minimal browser with a goofy streak: no accounts, no telemetry, no clutter. "
    "Make your dork (a little cartoon you), search with Doodle (Google’s or DuckDuckGo’s results, without the AI), "
    "block ads, save passwords, and pair it with Derp on your computer. It runs installed on its own or in LiveContainer, "
    "and uses what each one gives it."
)


def source(version, size, date):
    download = f"{REPO}/releases/download/v{version}/Derp.ipa"
    news = f"Derp {version}. What’s new: {REPO}/releases/tag/v{version}"
    return {
        "name": "Derp",
        "identifier": "io.github.kingbennet800.derp.source",
        "subtitle": "A fast, fluid browser with a goofy streak.",
        "description": ABOUT,
        "sourceURL": f"{REPO}/releases/latest/download/derp-source.json",
        "iconURL": f"https://raw.githubusercontent.com/KingBennet800/derp/v{version}/ios/AppIcon-1024.png",
        "website": "https://kingbennet800.github.io/derp/",
        "tintColor": "2F6FEB",
        "apps": [
            {
                "name": "Derp",
                "bundleIdentifier": "io.github.kingbennet800.derp",
                "developerName": "KingBennet800",
                "subtitle": "A fast, fluid browser with a goofy streak.",
                "localizedDescription": ABOUT,
                "iconURL": f"https://raw.githubusercontent.com/KingBennet800/derp/v{version}/ios/AppIcon-1024.png",
                "tintColor": "2F6FEB",
                "category": "utilities",
                "screenshotURLs": [],
                "version": version,
                "versionDate": date,
                "versionDescription": news,
                "downloadURL": download,
                "size": size,
                "versions": [
                    {
                        "version": version,
                        "buildVersion": version,
                        "date": date,
                        "localizedDescription": news,
                        "downloadURL": download,
                        "size": size,
                        "minOSVersion": "16.0",
                    }
                ],
                "appPermissions": {
                    "entitlements": [],
                    "privacy": {
                        "NSCameraUsageDescription": "To scan the pairing code Derp on your computer shows, and for websites you let use your camera.",
                        "NSMicrophoneUsageDescription": "For websites you let use your microphone.",
                        "NSLocationWhenInUseUsageDescription": "For websites you let see your location.",
                        "NSFaceIDUsageDescription": "To make sure it’s you before showing a saved password.",
                        "NSPhotoLibraryAddUsageDescription": "To save your screenshots with stickers to Photos.",
                    },
                },
            }
        ],
        "news": [],
    }


def main(version, ipa, out):
    date = datetime.date.today().isoformat()
    with open(out, "w", encoding="utf-8") as f:
        json.dump(source(version, os.path.getsize(ipa), date), f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"source.py: wrote {out} for Derp {version}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
