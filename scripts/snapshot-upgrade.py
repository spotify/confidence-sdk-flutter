"""Snapshot only the native fixture files reported by the stopped example app."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args)


device, report_path = sys.argv[1:]
report = json.loads(Path(report_path).read_text())
expected = json.loads(report["UPGRADE_EXPECTED"])
if expected["platform"] == "ios":
    container = Path(output("xcrun", "simctl", "get_app_container", device,
                            "com.example.confidenceFlutterSdkExample", "data").decode().strip())
for name in expected["files"]:
    if expected["platform"] == "ios":
        data = (container / "Library/Application Support" / name).read_bytes()
    else:
        data = output(os.environ.get("ADB_BIN", "adb"), "-s", device, "exec-out",
                      "run-as", "com.example.confidence_flutter_sdk_example",
                      "cat", "files/" + name)
    expected["files"][name] = base64.b64encode(data).decode()
report["UPGRADE_EXPECTED"] = json.dumps(expected)
Path(report_path).write_text(json.dumps(report))
