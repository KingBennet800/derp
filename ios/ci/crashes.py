#!/usr/bin/env python3
"""Shows Derp's crash reports from the simulators (the exception and the
crashed thread), and keeps them in screenshots/."""
import json
import pathlib
import shutil

out = pathlib.Path("screenshots")
out.mkdir(exist_ok=True)
reports = sorted(pathlib.Path.home().joinpath("Library/Logs/DiagnosticReports").glob("Derp*.ips"))
for report in reports:
    shutil.copyfile(report, out / report.name)
    text = report.read_text(errors="replace")
    header, _, body = text.partition("\n")
    print(f"::group::Crash report {report.name}")
    try:
        data = json.loads(body)
    except ValueError:
        print(text[:4000])
        print("::endgroup::")
        continue
    print("exception:", json.dumps(data.get("exception")))
    for key in ("asi", "lastExceptionBacktrace", "termination"):
        if key in data:
            print(f"{key}:", json.dumps(data[key])[:3000])
    images = data.get("usedImages", [])
    threads = data.get("threads", [])
    crashed = next((t for t in threads if t.get("triggered")), threads[0] if threads else None)
    if crashed:
        for frame in crashed.get("frames", [])[:40]:
            image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex", -1) < len(images) else "?"
            print(f"  {image:30} {frame.get('symbol', hex(frame.get('imageOffset', 0)))} {frame.get('sourceFile', '')}:{frame.get('sourceLine', '')}")
    print("::endgroup::")
if not reports:
    print("No crash reports from Derp.")
