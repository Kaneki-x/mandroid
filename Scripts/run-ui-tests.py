#!/usr/bin/env python3
"""Run real Android UI checks without activating windows or sharing guest data."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True, help='Debug Madroid.app')
parser.add_argument('--apk', type=Path)
parser.add_argument('--test', choices=['smoke', 'volume'], default='smoke')
parser.add_argument('--package', default='com.github.shadowsocks')
parser.add_argument('--sdk-data', type=Path, default=Path.home() / 'Library/Application Support/Madroid')
args = parser.parse_args()
app = args.app.resolve()
apk = args.apk.resolve() if args.apk else None
if not (app / 'Contents/MacOS/Madroid').is_file():
    parser.error('App executable must exist')
if args.test == 'smoke' and (apk is None or not apk.is_file()):
    parser.error('The smoke test requires --apk')
for name in ('sdk', 'tools'):
    if not (args.sdk_data / name).is_dir():
        parser.error(f'Missing installed {name} in --sdk-data')
root = Path(tempfile.mkdtemp(prefix='madroid-ui-', dir=Path.home() / 'Library/Caches'))
for name in ('sdk', 'tools'):
    (root / name).symlink_to((args.sdk_data / name).resolve(), target_is_directory=True)
control = root / 'control'
control.mkdir()
out = root / 'artifacts'
out.mkdir()
env = dict(os.environ, APP=str(app), APK=str(apk) if apk else "", PKG=args.package,
           UI_TEST_DATA_ROOT=str(root), UI_TEST_CONTROL=str(control), OUT=str(out))
print(f'Offscreen test data and artifacts: {root}', flush=True)
with (root / 'host.log').open('w') as log:
    process = subprocess.Popen([str(app / 'Contents/MacOS/Madroid'),
        '-dataRoot', str(root), '-uiTestControlDirectory', str(control),
        '-launcherStubs', 'NO'], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    script = 'volume-test.sh' if args.test == 'volume' else 'integration-test.sh'
    test = subprocess.Popen(['zsh', str(Path(__file__).with_name(script))],
                            env=env, start_new_session=True)
    try:
        while test.poll() is None and process.poll() is None:
            time.sleep(0.2)
        if test.poll() is None:
            raise RuntimeError(f'Test app exited early; see {root}/host.log')
    finally:
        if test.poll() is None:
            os.killpg(test.pid, signal.SIGTERM)
            test.wait(timeout=10)
        command = control / f'{time.time_ns()}.tmp'
        command.write_text('madroid://debug/quit')
        command.rename(command.with_suffix('.command'))
        try:
            process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    if process.returncode != 0:
        raise SystemExit(f'Test app exited {process.returncode}; see {root}/host.log')
raise SystemExit(test.returncode)
