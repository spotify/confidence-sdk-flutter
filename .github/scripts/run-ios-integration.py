#!/usr/bin/env python3
"""Bound Flutter's simulator VM discovery hang; retry only that startup race.

Remove when the pinned Flutter includes the fix for flutter/flutter#181771.
"""

import os
import queue
import signal
import subprocess
import sys
import threading
import time


def run(command, discovery_timeout=120):
    for attempt in range(2):
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, start_new_session=True,
        )
        output = queue.Queue()

        def read_output():
            for line in process.stdout:
                output.put(line)
            output.put(None)

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        deadline = None
        stalled = False
        while True:
            try:
                line = output.get(timeout=0.2)
            except queue.Empty:
                line = ""
            if line is None:
                break
            if line:
                print(line, end="", flush=True)
                if "Waiting for VM Service port to be available..." in line:
                    deadline = time.monotonic() + discovery_timeout
                elif "VM Service URL on device:" in line:
                    deadline = None
            if deadline is not None and time.monotonic() >= deadline:
                stalled = True
                print("VM Service discovery timed out.", flush=True)
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
                # Also stop descendants if the parent exited before them.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                break
        result = process.wait()
        reader.join(timeout=2)
        if not stalled:
            return result
        if attempt == 0:
            print("Retrying simulator launch once (flutter/flutter#181771).", flush=True)
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: run-ios-integration.py <command> [arguments...]")
    sys.exit(run(sys.argv[1:]))
