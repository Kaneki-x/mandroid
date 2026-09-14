#!/usr/bin/env python3
"""Real Android per-app HTTP proxy regression. Requires JDK 17 and Android build tools."""
import argparse
import base64
import concurrent.futures
import http.server
import json
import os
from pathlib import Path
import select
import shlex
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.parse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--android-sdk', type=Path, required=True)
parser.add_argument('--build-tools', default='36.1.0')
parser.add_argument('--platform', default='android-36')
parser.add_argument('--sdk-data', type=Path, default=Path.home() / 'Library/Application Support/Mandroid')
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent
root = Path(tempfile.mkdtemp(prefix='mandroid-ui-proxy-', dir=Path.home() / 'Library/Caches'))
print(f'Proxy test artifacts: {root}', flush=True)
for name in ('sdk', 'tools'):
    (root / name).symlink_to((args.sdk_data / name).resolve(), target_is_directory=True)
(root / 'control').mkdir()
(root / 'fixtures').mkdir()
log = (root / 'test.log').open('w')

def run(*command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, stdout=log, stderr=log, **kwargs)

# Three independent app UIDs. None of these fixtures is bundled in Mandroid.
bt = args.android_sdk / 'build-tools' / args.build_tools
android = args.android_sdk / 'platforms' / args.platform / 'android.jar'
key = root / 'fixtures/test.p12'
run('keytool', '-genkeypair', '-keystore', key, '-storepass', 'android', '-keypass', 'android', '-alias', 'test', '-keyalg', 'RSA', '-dname', 'CN=Mandroid fixture', '-validity', '2')
for name in ('a', 'b', 'c'):
    package = 'io.github.madeye.proxytest.' + name
    directory = root / 'fixtures' / name
    for sub in ('classes', 'dex'): (directory / sub).mkdir(parents=True)
    (directory / 'Main.java').write_text((repo / 'Tools/proxy-agent/tests/Client.java.in').read_text().replace('PACKAGE', package))
    (directory / 'AndroidManifest.xml').write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{package}" android:versionCode="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36"/><uses-permission android:name="android.permission.INTERNET"/><application android:label="Proxy test {name}" android:debuggable="true" android:usesCleartextTraffic="true"><activity android:name=".Main" android:exported="true"/></application></manifest>''')
    run('javac', '--release', '8', '-classpath', android, '-d', directory / 'classes', directory / 'Main.java')
    run(bt / 'd8', '--min-api', '29', '--lib', android, '--output', directory / 'dex', *list((directory / 'classes').rglob('*.class')))
    run(bt / 'aapt2', 'link', '-o', directory / 'unsigned.apk', '--manifest', directory / 'AndroidManifest.xml', '-I', android)
    run('zip', '-q', directory / 'unsigned.apk', 'classes.dex', cwd=directory / 'dex')
    run(bt / 'apksigner', 'sign', '--ks', key, '--ks-key-alias', 'test', '--ks-pass', 'pass:android', '--out', directory / 'app.apk', directory / 'unsigned.apk')

cert = root / 'fixtures/cert.pem'
run('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', root / 'fixtures/key.pem', '-out', cert, '-days', '1', '-subj', '/CN=proxy-test.local', '-addext', 'subjectAltName=DNS:proxy-test.local')
pin = base64.b64encode(ssl.PEM_cert_to_DER_cert(cert.read_text())).decode()

class Direct(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = self.server.body.encode()
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *args): pass

class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(15)
        header = bytearray()
        while not header.endswith(b'\r\n\r\n') and len(header) < 16384:
            chunk = self.request.recv(1)
            if not chunk: return
            header.extend(chunk)
        first = bytes(header).split(b'\r\n')[0].decode()
        with (root / 'proxy-requests.log').open('a') as out: out.write(self.server.tag + ' ' + first + '\n')
        if first.startswith('CONNECT '):
            with socket.create_connection(('127.0.0.1', secure.server_address[1])) as upstream:
                self.request.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
                while True:
                    readable, _, _ = select.select([self.request, upstream], [], [], 15)
                    if not readable: return
                    for source in readable:
                        data = source.recv(16384)
                        if not data: return
                        (upstream if source is self.request else self.request).sendall(data)
        else:
            body = self.server.tag.encode()
            self.request.sendall(b'HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)

servers = []
def start_server(server):
    server.daemon_threads = True
    servers.append(server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server

direct = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Direct); direct.body = 'DIRECT'; start_server(direct)
secure = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Direct); secure.body = 'TLS_OK'
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); tls.load_cert_chain(cert, root / 'fixtures/key.pem')
secure.socket = tls.wrap_socket(secure.socket, server_side=True); start_server(secure)
proxies = {}
for name in ('a', 'b'):
    server = socketserver.ThreadingTCPServer(('127.0.0.1', 0), Proxy); server.tag = 'PROXY_' + name.upper()
    proxies[name] = start_server(server)

process = None
adb = None

def command(url):
    path = root / 'control' / f'{time.time_ns()}.tmp'; path.write_text(url); path.rename(path.with_suffix('.command'))

def wait_for(check, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value: return value
        time.sleep(.25)
    raise AssertionError('Timed out; inspect ' + str(root))

def launch():
    global process, adb
    process = subprocess.Popen([str(args.app / 'Contents/MacOS/Mandroid'), '-dataRoot', str(root), '-uiTestControlDirectory', str(root / 'control'), '-launcherStubs', 'NO'], stdout=log, stderr=log, start_new_session=True)
    def ready():
        command('mandroid://debug/snapshot?dir=' + str(root / 'status'))
        time.sleep(.25)
        file = root / 'status/state.txt'
        if process.poll() is not None: raise AssertionError('Test app exited early')
        if not file.exists(): return None
        state = dict(line.split('=', 1) for line in file.read_text().splitlines() if '=' in line)
        return state if state.get('state') == 'ready' else None
    state = wait_for(ready, 300)
    adb = [str(args.sdk_data / 'sdk/platform-tools/adb'), '-P', state['adbPort'], '-s', state['serial']]

def shell(*parts, check=True):
    return subprocess.run(adb + ['shell', shlex.join([str(x) for x in parts])], check=check, capture_output=True, text=True)

def configure(name, port):
    package = 'io.github.madeye.proxytest.' + name
    query = dict(pkg=package, host='localhost', port=port) if port else dict(pkg=package, off='1')
    command('mandroid://debug/proxy?' + urllib.parse.urlencode(query))
    def saved():
        file = root / 'app-proxies.json'
        if not file.exists(): return False
        value = json.loads(file.read_text()).get(package)
        return value is None if port is None else value is not None and value['port'] == port
    wait_for(saved, 45)

def request(name, url='http://198.18.0.1/probe', certificate=None):
    package = 'io.github.madeye.proxytest.' + name
    shell('run-as', package, 'rm', '-f', 'files/result')
    parts = ['am', 'start', '-W', '-n', package + '/.Main', '--es', 'url', url]
    if certificate: parts += ['--es', 'certificate', certificate]
    shell(*parts)
    def result():
        output = shell('run-as', package, 'cat', 'files/result', check=False)
        return json.loads(output.stdout) if output.returncode == 0 else None
    return wait_for(result, 25)

def stop():
    if process is not None and process.poll() is None:
        command('mandroid://debug/quit')
        process.wait(timeout=120)
    state = root / 'status/state.txt'
    if state.exists(): state.unlink()

try:
    launch()
    for name in ('a', 'b', 'c'): run(*adb, 'install', '-r', root / 'fixtures' / name / 'app.apk')
    configure('a', proxies['a'].server_address[1]); configure('b', proxies['b'].server_address[1])
    with concurrent.futures.ThreadPoolExecutor() as pool: results = list(pool.map(request, ['a', 'b']))
    assert [x.get('body') for x in results] == ['PROXY_A', 'PROXY_B'], results
    direct_url = f'http://10.0.2.2:{direct.server_address[1]}/direct'
    result = request('c', direct_url)
    assert result.get('body') == 'DIRECT' and 'DIRECT' in result['proxy'], result
    result = request('a', f'https://proxy-test.local:{secure.server_address[1]}/tls', pin)
    assert result.get('body') == 'TLS_OK', result
    configure('a', None)
    assert request('a', direct_url).get('body') == 'DIRECT'
    assert request('b').get('body') == 'PROXY_B'
    stop(); launch()
    assert request('b').get('body') == 'PROXY_B'
    with socket.socket() as unused: unused.bind(('127.0.0.1', 0)); unavailable = unused.getsockname()[1]
    configure('b', unavailable)
    result = request('b', direct_url); assert 'error' in result, result
    configure('b', None)
    assert request('b', direct_url).get('body') == 'DIRECT'
    print('PASS: separate concurrent proxies, unconfigured direct app, HTTPS CONNECT, independent removal, restart persistence, unreachable proxy, and disable-all', flush=True)
finally:
    if adb is not None:
        with (root / 'android-proxy.log').open('w') as out:
            subprocess.run(adb + ['logcat', '-d', '-s', 'MandroidProxy:V', 'AndroidRuntime:E'], stdout=out, stderr=out)
    try: stop()
    finally:
        for server in servers: server.shutdown(); server.server_close()
        log.close()
