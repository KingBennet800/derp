#!/usr/bin/env python3
"""Runs one of Derp for iOS's test runs in CI, with a time limit, showing its
progress as it goes. If it runs out of time, it keeps what the simulator
shows and what Derp logged, to see why.

    python3 ios/ci/run.py NAME SIMULATOR_ID MINUTES -only-testing:DerpTests ...
"""
import os
import pathlib
import re
import subprocess
import sys
import time

name, device, minutes, *extra = sys.argv[1:]
temp = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp"))
out = pathlib.Path("screenshots")
out.mkdir(exist_ok=True)
version = pathlib.Path("VERSION").read_text().strip()
log = (temp / f"{name}.log").open("w")
command = [
    "xcodebuild", "test-without-building",
    "-project", "ios/Derp.xcodeproj", "-scheme", "Derp",
    "-derivedDataPath", str(temp / "dd"),
    "-destination", f"id={device}",
    "-resultBundlePath", str(temp / f"{name}.xcresult"),
    "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "600",
    f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={version}",
    *extra,
]
shown = re.compile(r"^(Test (Case|Suite)|.*error:|.*: (failed|passed)|\*\*|Derp: |.*XCTAssert|.*Restarting after unexpected exit|.*Failing tests:)")
started = time.time()
process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
deadline = started + float(minutes) * 60
succeeded = False
timed_out = False
import selectors
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
while True:
    if time.time() > deadline:
        timed_out = True
        break
    if not selector.select(timeout=5):
        if process.poll() is not None:
            break
        continue
    line = process.stdout.readline()
    if not line:
        break
    log.write(line)
    if "** TEST SUCCEEDED **" in line or "** TEST EXECUTE SUCCEEDED **" in line:
        succeeded = True
    if shown.match(line):
        print(f"[{int(time.time() - started):4d}s] {line.rstrip()}", flush=True)

if timed_out:
    print(f"::error::{name} ran out of time ({minutes} minutes)", flush=True)
    subprocess.run(["xcrun", "simctl", "io", device, "screenshot", str(out / f"{name}-stuck.png")])
    shown_log = subprocess.run(
        ["xcrun", "simctl", "spawn", device, "log", "show", "--last", "10m", "--style", "compact",
         "--predicate", 'process == "Derp" OR eventMessage CONTAINS "Derp"'],
        capture_output=True, text=True,
    ).stdout
    (out / f"{name}-stuck.log").write_text(shown_log)
    print("\n".join(shown_log.splitlines()[-60:]), flush=True)
    process.kill()
else:
    process.wait()
    for line in process.stdout:
        log.write(line)
log.close()
if not succeeded:
    text = (temp / f"{name}.log").read_text()
    print("::group::What went wrong", flush=True)
    for match in re.finditer(r"(?m)^.*(error:|failed|XCTAssert|Restarting after unexpected exit).*$", text):
        print(match.group(0))
    print("::endgroup::", flush=True)
    sys.exit(1)
print(f"{name}: passed in {int(time.time() - started)}s")
