#!/usr/bin/env python3
"""Verify Debug recording lifecycle with real MP4 output and isolated app data."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
from urllib.parse import urlencode

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
args = parser.parse_args()
executable = args.app.resolve() / 'Contents/MacOS/Mandroid'
if not executable.is_file() or not shutil.which('ffprobe'):
    parser.error('A built Debug Mandroid.app and ffprobe are required')
root = Path(tempfile.mkdtemp(prefix='mandroid-ui-recording-', dir=Path.home() / 'Library/Caches'))
control = root / 'control'
control.mkdir()
log = root / 'logs/app.log'
print(f'Recording test artifacts: {root}', flush=True)


def command(name, **query):
    path = control / f'{time.time_ns()}.tmp'
    path.write_text('mandroid://debug/' + name + '?' + urlencode(query))
    path.rename(path.with_suffix('.command'))


def logs():
    return log.read_text() if log.exists() else ''


def wait_for(predicate, description, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        if process.poll() is not None:
            raise RuntimeError(f'App exited {process.returncode}: {description}')
        time.sleep(0.05)
    raise TimeoutError(description)


def record(path, seconds=1.2):
    command('record', file=path, secs=seconds, fps=10, scale=0.25, composite=1)


def verify(path):
    data = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,width,height,nb_read_frames:format=duration',
        '-of', 'json', str(path)], text=True))
    video = data['streams'][0]
    assert video['codec_name'] == 'h264', data
    assert video['width'] > 0 and video['height'] > 0, data
    assert int(video['nb_read_frames']) >= 2, data
    assert 0.1 < float(data['format']['duration']) < 10, data
    print(f'PASS {path.name}: {data}', flush=True)


with (root / 'host.log').open('w') as host_log:
    process = subprocess.Popen([
        str(executable), '-dataRoot', str(root), '-uiTestControlDirectory', str(control),
        '-launcherStubs', 'NO', '-autoSetup', 'NO'],
        stdout=host_log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        # Timed completion must produce a readable, finalized file.
        timed = root / 'timed.mp4'
        record(timed)
        wait_for(lambda: f'frames → {timed}' in logs(), 'timed recording completion')
        verify(timed)

        # Repeated stop must join the same finalization, without a second writer stop.
        early = root / 'early.mp4'
        record(early, 30)
        wait_for(lambda: f'fps → {early}' in logs(), 'early recording start')
        time.sleep(0.6)
        command('stoprecord')
        command('stoprecord')
        wait_for(lambda: f'frames → {early}' in logs(), 'early recording completion')
        verify(early)

        # Replacing an active recording at the same path must finish the old writer first.
        replaced = root / 'replaced.mp4'
        record(replaced, 30)
        wait_for(lambda: f'fps → {replaced}' in logs(), 'replacement recording start')
        time.sleep(0.6)
        record(replaced)
        wait_for(lambda: logs().count(f'frames → {replaced}') == 2, 'replacement completion')
        verify(replaced)

        # Invalid arguments must not remove an existing destination.
        sentinel = root / 'invalid.mp4'
        sentinel.write_bytes(b'preserve existing output')
        record(sentinel, 'nan')
        wait_for(lambda: 'invalid duration' in logs(), 'invalid argument rejection')
        assert sentinel.read_bytes() == b'preserve existing output'

        # Quit must await finalization before exiting.
        quitting = root / 'quit.mp4'
        record(quitting, 30)
        wait_for(lambda: f'fps → {quitting}' in logs(), 'quit recording start')
        time.sleep(0.6)
        command('quit')
        assert process.wait(timeout=120) == 0
        verify(quitting)
        assert 'record: failed' not in logs(), logs()
        print('PASS: timed completion, repeated stop, replacement, invalid input, and quit', flush=True)
    finally:
        if process.poll() is None:
            command('quit')
            try:
                process.wait(timeout=120)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
