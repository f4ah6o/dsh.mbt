#!/usr/bin/env python3
"""Test a packaged Linux ELF on an owned, authenticated virtual desktop.

Requires Xvfb, weston, xdotool, xwininfo, xdpyinfo and Japanese fonts. Never
connects to the inherited desktop. All input goes through XTest and Weston.
Artifacts survive failures; virtual displays and processes do not.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time

WIDTH, HEIGHT = 1120, 760
EXPECTED_TEXT = 'Create and verify a durable file. via Linux keyboard'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def auth_file(path, number, cookie):
    fields = (b'', str(number).encode(), b'MIT-MAGIC-COOKIE-1', cookie)
    path.write_bytes(struct.pack('>H', 65535) + b''.join(
        struct.pack('>H', len(field)) + field for field in fields))
    path.chmod(0o600)


def parse_click(line):
    value = json.loads(line.removeprefix('DSH_DESKTOP_INPUT '))
    require(isinstance(value, dict) and set(value) == {'x', 'y'}, 'Invalid input request')
    for key, limit in [('x', WIDTH), ('y', HEIGHT)]:
        coordinate = value[key]
        require(type(coordinate) in (int, float) and math.isfinite(coordinate)
                and 0 <= coordinate < limit, 'Unsafe input coordinate')
    return int(value['x']), int(value['y'])


def marker(log, name, expected):
    matches = [json.loads(line[len(name) + 1:]) for line in log.splitlines()
               if line.startswith(name + ' ')]
    require(len(matches) == 1, f'Expected exactly one {name} marker')
    require(all(type(matches[0].get(k)) is type(v) and matches[0].get(k) == v
                for k, v in expected.items()), f'Failed {name} oracle: {matches[0]}')
    return matches[0]


def ppm_info(path):
    data = path.read_bytes()
    # GPUI writes binary P6. Accept comments in its header without consuming
    # whitespace-valued bytes from the actual pixel payload.
    header = re.match(rb'P6\s+(?:#[^\n]*\n\s*)*(\d+)\s+(\d+)\s+(\d+)(?:\r\n|\s)', data)
    require(header is not None, f'Invalid P6 frame: {path}')
    width, height, maximum = map(int, header.groups())
    pixels = data[header.end():]
    require(width > 0 and height > 0 and maximum == 255
            and len(pixels) == width * height * 3, f'Truncated frame: {path}')
    require(len(set(pixels)) > 1, f'Empty/uniform frame: {path}')
    return {'width': width, 'height': height, 'sha256': hashlib.sha256(data).hexdigest()}


def wait_for(predicate, timeout, label):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise RuntimeError('Timed out waiting for ' + label)


def pending_pid(path):
    try:
        text = path.read_text()
    except FileNotFoundError:
        return None
    # The fixture terminates its one printf with a newline. An empty/partial
    # file is not a PID and must not race the shell's open-then-write sequence.
    if not text.endswith('\n'):
        return None
    require(re.fullmatch(r'[0-9]+\n', text) is not None and int(text) > 1,
            'Invalid hook child PID')
    return int(text)


def process_running(pid):
    try:
        # Zombies have exited; their reaping belongs to their adopting init.
        return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[0] != 'Z'
    except FileNotFoundError:
        return False


def process_info(pid):
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return {'parent': int(fields[1]), 'starttime': fields[19], 'state': fields[0]}
    except (FileNotFoundError, ProcessLookupError):
        return None


def same_process_running(pid, observed):
    current = process_info(pid)
    return current is not None and current['state'] != 'Z' and current['starttime'] == observed['starttime']


def process_tree(root):
    candidates = {}
    for path in Path('/proc').iterdir():
        if path.name.isdecimal():
            info = process_info(int(path.name))
            if info is not None:
                candidates[int(path.name)] = info
    descendants = {}
    parents = {root}
    while parents:
        children = {pid: info for pid, info in candidates.items()
                    if info['parent'] in parents and pid not in descendants}
        descendants.update(children)
        parents = set(children)
    return descendants


class Harness:
    def __init__(self, binary, output, runtime):
        self.binary, self.output, self.runtime = binary, output, runtime
        self.processes, self.streams = [], []
        self.owned_descendants = {}
        self.env = os.environ.copy()
        for key in list(self.env):
            if (key.startswith(('DSH_', 'GPUI_', 'DEEPSEEK_', 'OPENAI_', 'LD_', 'WESTON_'))
                    or key in ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'XAUTHORITY', 'FONTCONFIG_FILE', 'FONTCONFIG_PATH')):
                self.env.pop(key, None)
        self.env.update(XDG_RUNTIME_DIR=str(runtime), XAUTHORITY=str(runtime / 'Xauthority'),
                        LIBGL_ALWAYS_SOFTWARE='1', XDG_SESSION_TYPE='wayland',
                        XDG_CACHE_HOME=str(output / 'cache'))
        self.window = None

    def launch(self, args, label, env=None):
        log = self.output / (label + '.log')
        stream = log.open('wb')
        self.streams.append(stream)
        process = subprocess.Popen(args, cwd=self.output, env=env or self.env,
                                   stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        self.processes.append(process)
        return process, log

    def command(self, args, check=True):
        return subprocess.run(args, env=self.env, cwd=self.output, text=True,
                              capture_output=True, timeout=10, check=check)

    def start_display(self):
        inherited = os.environ.get('DISPLAY', '')
        number = 1000 + secrets.randbelow(20000)
        require(not re.search(r':' + str(number) + r'(?:\.\d+)?$', inherited),
                'Refusing inherited display')
        require(not Path(f'/tmp/.X{number}-lock').exists()
                and not Path(f'/tmp/.X11-unix/X{number}').exists(), 'Display already occupied')
        auth_file(self.runtime / 'Xauthority', number, secrets.token_bytes(16))
        self.env['DISPLAY'] = f':{number}'
        xvfb, _ = self.launch(['Xvfb', self.env['DISPLAY'], '-screen', '0', '1280x900x24',
                              '-nolisten', 'tcp', '-auth', self.env['XAUTHORITY']], 'xvfb')
        def ready():
            require(xvfb.poll() is None, 'Owned Xvfb exited; see xvfb.log')
            return self.command(['xdpyinfo'], check=False).returncode == 0
        wait_for(ready, 15, 'private authenticated Xvfb')
        return {'private_display': self.env['DISPLAY'], 'inherited_display_excluded': inherited}

    def compositor(self, shell, label, width=WIDTH, height=HEIGHT):
        socket = label
        help_text = self.command(['weston', '--help'], check=False)
        # Legacy X11 Weston defaults to GL (its --use-gl flag is headless-only).
        renderer = ['--renderer=gl'] if '--renderer' in help_text.stdout + help_text.stderr else []
        weston, _ = self.launch(['weston', '--backend=x11-backend.so', *renderer,
                                '--shell=' + shell + '-shell.so', '--socket=' + socket,
                                f'--width={width}', f'--height={height}', '--idle-time=0',
                                '--no-config', '--log=' + str(self.output / (label + '-weston.log'))], label)
        def ready():
            require(weston.poll() is None, 'Owned Weston exited; inspect compositor logs')
            return (self.runtime / socket).exists()
        wait_for(ready, 15, 'owned Weston socket')
        self.env['WAYLAND_DISPLAY'] = socket
        if shell == 'kiosk':
            def discover():
                result = self.command(['xdotool', 'search', '--onlyvisible', '--name',
                                       '^Weston Compositor'], check=False)
                ids = result.stdout.split()
                if len(ids) != 1:
                    return None
                candidate = int(ids[0])
                tree = self.command(['xwininfo', '-root', '-tree']).stdout
                require(re.search(r'\b' + re.escape(hex(candidate)) + r'\b', tree) is not None,
                        'Weston window is absent from owned X root tree')
                log = (self.output / (label + '-weston.log')).read_text(errors='replace')
                logged = re.search(r'x11 output .*?window id (\d+)', log)
                require(logged is None or int(logged[1]) == candidate, 'Weston window ID mismatch')
                geometry = self.command(['xdotool', 'getwindowgeometry', '--shell', str(candidate)]).stdout
                require(f'WIDTH={WIDTH}\n' in geometry and f'HEIGHT={HEIGHT}\n' in geometry,
                        'Unexpected Weston input geometry')
                return candidate
            self.window = wait_for(discover, 15, 'verified private Weston X window')
        return weston

    def input_click(self, coordinates, first):
        window = str(self.window)
        self.command(['xdotool', 'windowfocus', '--sync', window])
        require(self.command(['xdotool', 'getwindowfocus']).stdout.strip() == window,
                'Private Weston focus verification failed')
        def click(x, y):
            self.command(['xdotool', 'mousemove', '--sync', '--window', window,
                          str(x), str(y), 'click', '1'])
        if first:
            click(400, 650)
            self.command(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'])
            self.command(['xdotool', 'type', '--clearmodifiers', '--delay', '20', '--', EXPECTED_TEXT])
        click(*coordinates)

    def app(self, label, flags):
        root = self.output / label
        root.mkdir()
        # NativeRuntime canonicalizes the workspace before opening it.
        (root / 'workspace').mkdir(mode=0o700)
        (root / 'data').mkdir(mode=0o700)
        tmp = root / 'tmp'
        tmp.mkdir(mode=0o700)
        env = self.env.copy()
        env.update(TMPDIR=str(tmp), GPUI_NATIVE_E2E='1', WAYLAND_DEBUG='client')
        if '--offline-e2e' in flags:
            env.update(DSH_DESKTOP_EXTERNAL_INPUT='1', DSH_DESKTOP_E2E_TEXT=EXPECTED_TEXT)
        args = [str(self.binary), 'desktop', '--demo', '--data-dir', str(root / 'data'),
                '--workspace', str(root / 'workspace'), '--frame-output', str(root / 'transcript.ppm'), *flags]
        process, log = self.launch(args, label + '-app', env)
        return process, log, root, tmp

    def run_until_exit(self, app, log, input_enabled=False, interrupt_pid_file=None):
        count, handled = 0, 0
        deadline = time.monotonic() + 90
        while True:
            text = log.read_text(errors='replace')
            lines = text.splitlines(keepends=True)
            complete = [line.rstrip('\r\n') for line in lines if line.endswith('\n')]
            for line in complete[handled:]:
                if line.startswith('DSH_DESKTOP_INPUT '):
                    require(input_enabled and count < 2, 'Unexpected/excess input request')
                    self.input_click(parse_click(line), count == 0)
                    count += 1
            handled = len(complete)
            child = pending_pid(interrupt_pid_file) if interrupt_pid_file is not None else None
            if child is not None:
                require(count == 2, 'Worker started before approval input')
                require(child > 1 and process_running(child), 'Hook child was not running before TERM')
                descendants = process_tree(app.pid)
                require(child in descendants, 'Hook PID is not an owned GUI descendant')
                self.owned_descendants.update(descendants)
                app.terminate()
                app.wait(timeout=20)
                require(app.returncode == 143, f'Active TERM exited {app.returncode}, expected supervisor status 143')
                wait_for(lambda: all(not same_process_running(pid, info) for pid, info in descendants.items()),
                         5, 'cancelled worker process tree')
                return {'returncode': app.returncode, 'child_pid': child,
                        'child_running_before_term': True, 'child_running_after_term': False,
                        'observed_descendants': descendants, 'all_observed_descendants_exited': True}, count
            if app.poll() is not None:
                require(interrupt_pid_file is None, 'GUI exited before active-worker TERM test')
                # The process might exit between reading its log and poll().
                if log.read_text(errors='replace') != text:
                    continue
                require(app.returncode == 0, f'Packaged desktop exited {app.returncode}; see {log}')
                return text, count
            require(time.monotonic() < deadline, 'Packaged desktop exceeded 90-second deadline')
            time.sleep(0.05)

    @staticmethod
    def clean_payload(tmp):
        require(not list(tmp.iterdir()), f'Launcher leaked extracted payload/temp files in {tmp}')

    def stop(self, process):
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)

    def cleanup(self):
        for pid, info in self.owned_descendants.items():
            if same_process_running(pid, info):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for process in reversed(self.processes):
            # An unreaped Popen child owns its PID even if it exits between poll
            # and killpg. Never signal a group after the leader has been reaped.
            if process.poll() is not None:
                continue
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                continue
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                process.wait(timeout=3)
        for stream in self.streams:
            stream.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path, help='packaged raw dsh ELF')
    parser.add_argument('output', nargs='?', type=Path, help='fresh artifact directory')
    args = parser.parse_args()
    binary = args.binary.resolve()
    require(binary.is_file() and os.access(binary, os.X_OK), 'Missing executable packaged dsh')
    with binary.open('rb') as stream:
        require(stream.read(4) == b'\x7fELF', 'Expected a raw ELF, not a release archive')
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='dsh-linux-smoke-artifacts-'))
    require(not output.exists() or not any(output.iterdir()), 'Refusing nonempty artifact directory')
    output.mkdir(parents=True, exist_ok=True)
    result = {'status': 'failed', 'binary': str(binary),
              'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'input_route': 'xdotool XTest -> authenticated private Xvfb -> Weston -> GPUI'}
    harness = None
    try:
        for tool in ['Xvfb', 'weston', 'xdotool', 'xwininfo', 'xdpyinfo']:
            require(shutil.which(tool), 'Missing required tool: ' + tool)
        with tempfile.TemporaryDirectory(prefix='dsh-gui-', dir='/tmp') as runtime:
            Path(runtime).chmod(0o700)
            harness = Harness(binary, output, Path(runtime))
            try:
                result.update(harness.start_display())
                kiosk = harness.compositor('kiosk', 'kiosk')
                app, log, root, tmp = harness.app('demo', ['--offline-e2e'])
                text, clicks = harness.run_until_exit(app, log, input_enabled=True)
                require(clicks == 2, f'Expected two native clicks, saw {clicks}')
                result['demo'] = marker(text, 'DSH_DESKTOP_DEMO', {
                    'native_events': True, 'tool_approval': 'approved', 'completed': True,
                    'workspace_write': True, 'reload': 'passed', 'japanese_frame': 'passed'})
                require((root / 'workspace/native-demo.txt').read_text() == 'durable native tool result',
                        'Durable workspace write mismatch')
                result['frames'] = {name: ppm_info(root / name) for name in [
                    'transcript.ppm.initial.ppm', 'transcript.ppm', 'transcript.ppm.settings.ppm']}
                harness.clean_payload(tmp)
                result['input_requests'] = clicks
                hook = output / 'shutdown-hooks.json'
                hook.write_text(json.dumps({'PreToolUse': [{'matcher': 'write', 'hooks': [{
                    'type': 'command',
                    'command': 'cat >/dev/null; (trap \"\" TERM; exec sleep 60) & child=$!; '
                               'printf \"%s\\n\" \"$child\" > \"${CLAUDE_PROJECT_DIR}/shutdown-child.pid\"; '
                               'wait; printf \"{}\"'}]}]}))
                app, log, root, tmp = harness.app('active-term', ['--offline-e2e', '--hooks-config', str(hook)])
                shutdown, clicks = harness.run_until_exit(
                    app, log, input_enabled=True,
                    interrupt_pid_file=root / 'workspace/shutdown-child.pid')
                require(clicks == 2, 'Active-worker test did not approve through native input')
                harness.clean_payload(tmp)
                require(not (root / 'workspace/native-demo.txt').exists(),
                        'Cancelled worker performed a late workspace write')
                shutdown['payload_cleanup'] = True
                result['active_worker_term'] = shutdown
                harness.stop(kiosk)
                # A normal shell permits the resize that kiosk fullscreen ignores.
                harness.compositor('desktop', 'lifecycle', width=1280, height=900)
                app, log, _, tmp = harness.app('lifecycle', ['--smoke'])
                text, _ = harness.run_until_exit(app, log)
                result['lifecycle'] = marker(text, 'DSH_DESKTOP_SMOKE', {
                    'frame': True, 'resized': True, 'close_requested': True, 'destroyed': True})
                harness.clean_payload(tmp)
                app, log, _, tmp = harness.app('term', [])
                wait_for(lambda: list(tmp.iterdir()) or app.poll() is not None, 15, 'extracted running GUI')
                def idle_frame():
                    require(app.poll() is None, 'Idle GUI exited before presenting a frame')
                    return re.search(r'wl_callback(?:@|#)\d+\.done\(', log.read_text(errors='replace'))
                wait_for(idle_frame, 20, 'idle GUI Wayland frame callback')
                require(app.poll() is None, 'Idle GUI exited before TERM test')
                result['term_extracted_entries'] = [p.name for p in tmp.iterdir()]
                require(result['term_extracted_entries'], 'TERM test did not observe extracted payload')
                harness.stop(app)
                require(app.returncode == 143, f'Idle TERM exited {app.returncode}, expected supervisor status 143')
                harness.clean_payload(tmp)
                result['term'] = {'returncode': app.returncode, 'payload_cleanup': True}
                result['status'] = 'passed'
            finally:
                harness.cleanup()
    except Exception as error:
        result['error'] = str(error)
    (output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    print('Artifacts: ' + str(output))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
