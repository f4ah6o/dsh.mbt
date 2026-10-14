#!/usr/bin/env python3
"""Exercise packaged web startup outside the checkout, without user data/accounts."""
import os
import errno
from pathlib import Path
import re
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

binary = str(Path(sys.argv[1]).resolve())
# Rebuild the environment rather than inheriting provider credentials/configuration.
base_env = {key: os.environ[key] for key in ('PATH', 'SYSTEMROOT', 'LD_LIBRARY_PATH') if key in os.environ}


def run_server(root, args, expected_port=None, fail=False, extra_env=None):
    root.mkdir()
    env = dict(base_env, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'))
    env.update(extra_env or {})
    with (root / 'output.log').open('w+') as log:
        child = subprocess.Popen([binary, 'web', *args], cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                log.seek(0)
                output = log.read()
                match = re.search(r'^native service listening at http://127\.0\.0\.1:(\d+)$', output, re.M)
                if match or child.poll() is not None:
                    break
                time.sleep(.025)
            if fail:
                assert child.wait(timeout=5) == 1, output
                log.seek(0)
                output = log.read()
                assert 'cannot listen on 127.0.0.1:' in output, output
                assert 'OSError' in output and '--port 0' in output, output
                assert not match, output
                assert 'selecting an available' not in output, output
                return output
            assert match and child.poll() is None, output
            port = int(match[1])
            if expected_port is not None:
                assert port == expected_port, output
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=5) as response:
                assert response.status == 200
                assert b'/moonbit/browser.js' in response.read()
            child.send_signal(signal.SIGTERM)
            assert child.wait(timeout=5) == 0
            # The service must have closed its store after either a clean stop
            # or a failed bind; verify below by reopening the same data directory.
            return port, output
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


with tempfile.TemporaryDirectory(prefix='dsh-web-listener-') as temp:
    root = Path(temp)
    with socket.socket() as default_occupant:
        default_occupant.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            default_occupant.bind(('127.0.0.1', 3080))
            owns_default = True
            default_occupant.listen()
        except OSError as error:
            if error.errno != errno.EADDRINUSE:
                raise
            owns_default = False
            print('SKIP owning/clean default port: 3080 already occupied; testing fallback without touching its owner')
        port, output = run_server(root / 'default-conflict', [])
        assert port != 3080 and 'default port 3080 is already in use' in output, output
        if owns_default:
            with socket.create_connection(('127.0.0.1', 3080), timeout=3):
                accepted, _ = default_occupant.accept()
                accepted.close()
    if owns_default:
        run_server(root / 'default-clean', [], expected_port=3080)
    with socket.socket() as occupant:
        occupant.bind(('127.0.0.1', 0))
        occupant.listen()
        requested_port = occupant.getsockname()[1]
        failure = run_server(root / 'explicit-conflict', ['--port', str(requested_port)], fail=True)
        assert f'127.0.0.1:{requested_port}' in failure, failure
        print('Explicit conflict:', failure.strip())
        # The original socket is still the listener; no killing or port sharing.
        with socket.create_connection(('127.0.0.1', requested_port), timeout=3):
            accepted, _ = occupant.accept()
            accepted.close()
        run_server(root / 'ephemeral', ['--port', '0'])
    if sys.platform.startswith('linux') and shutil.which('cc'):
        # Controlled syscall failure distinguishes a true conflict from sandbox,
        # permission, or network restrictions. No fallback is allowed for EACCES.
        shim = root / 'deny-bind.c'
        shim.write_text('#include <sys/socket.h>\n#include <errno.h>\n'
                        'int bind(int fd, const struct sockaddr *addr, socklen_t n) '
                        '{ (void)fd; (void)addr; (void)n; errno=EACCES; return -1; }\n')
        library = root / 'deny-bind.so'
        subprocess.run(['cc', '-shared', '-fPIC', str(shim), '-o', str(library)], check=True)
        denied = run_server(root / 'permission-denied', [], fail=True,
                            extra_env={'LD_PRELOAD': str(library), 'LC_ALL': 'C'})
        assert 'Permission denied' in denied, denied
        print('Denied bind:', denied.strip())
    # Reuse the rejected startup's store; failed bind must release its lock.
    run_server(root / 'reopen', ['--data-dir', str(root / 'explicit-conflict' / '.dsh.mbt'), '--port', '0'])
print('PASS: plain web, default conflict fallback, strict explicit conflict, occupied socket preservation, HTTP, ephemeral startup, and lock release')
