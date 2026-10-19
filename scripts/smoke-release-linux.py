#!/usr/bin/env python3
"""Test a packaged Linux ELF on an owned, authenticated virtual desktop.

Requires Xvfb, xdotool, xwininfo, xdpyinfo and Japanese fonts, plus Weston for
Wayland or xprop/xclip for native X11. Never connects to the inherited desktop.
X11 mode connects the app directly to Xvfb; no Weston or XWayland is involved.
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
CLIPBOARD_TEXT = 'Create and verify a durable file. 日本語'
X11_EXPECTED_TEXT = CLIPBOARD_TEXT + ' via Linux keyboard'
CLIPBOARD_DIAGNOSTIC_CHARACTERS = 1024
# desktop-shell initializes Weston's text-input-v1 support; kiosk-shell does not.
# Disable chrome/animations so the app-sized output remains the input viewport.
WESTON_CONFIG = """[shell]
animation=none
close-animation=none
startup-animation=none
focus-animation=none
panel-position=none
locking=false
"""


def require_text_input_manager(text):
    require(re.search(r'wl_registry(?:@|#)\d+\.global\(\d+, "zwp_text_input_manager_v1", [1-9]\d*\)', text),
            'Owned Weston did not advertise text-input-v1; inspect the app protocol log')


# Run in a subprocess with the harness's private DISPLAY and XAUTHORITY. Using
# XSendEvent with WM_DELETE_WINDOW requests normal close; xdotool windowclose
# destroys the window and would bypass the lifecycle being tested.
X11_CLOSE_HELPER = r'''
import ctypes as c
import os
import sys
class Data(c.Union):
    _fields_ = [('b', c.c_char * 20), ('s', c.c_short * 10), ('l', c.c_long * 5)]
class ClientMessage(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
                ('display', c.c_void_p), ('window', c.c_ulong),
                ('message_type', c.c_ulong), ('format', c.c_int), ('data', Data)]
class Event(c.Union):
    _fields_ = [('client', ClientMessage), ('pad', c.c_long * 24)]
x = c.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes = [c.c_char_p]
x.XOpenDisplay.restype = c.c_void_p
x.XInternAtom.argtypes = [c.c_void_p, c.c_char_p, c.c_int]
x.XInternAtom.restype = c.c_ulong
x.XSendEvent.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.POINTER(Event)]
x.XSendEvent.restype = c.c_int
x.XSync.argtypes = [c.c_void_p, c.c_int]
x.XCloseDisplay.argtypes = [c.c_void_p]
display = x.XOpenDisplay(os.environ['DISPLAY'].encode())
if not display:
    sys.exit('Cannot open owned X display')
try:
    protocols = x.XInternAtom(display, b'WM_PROTOCOLS', 1)
    delete = x.XInternAtom(display, b'WM_DELETE_WINDOW', 1)
    if not protocols or not delete:
        sys.exit('Owned X window has no close protocol')
    window = int(sys.argv[1])
    event = Event()
    event.client.type = 33
    event.client.display = display
    event.client.window = window
    event.client.message_type = protocols
    event.client.format = 32
    event.client.data.l[0] = delete
    if not x.XSendEvent(display, window, 0, 0, c.byref(event)):
        sys.exit('WM_DELETE_WINDOW send failed')
    x.XSync(display, 0)
finally:
    x.XCloseDisplay(display)
'''


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


def logged_window(log, width, height):
    outputs = {tuple(map(int, match)) for match in re.findall(
        r'x11 output (\d+)x(\d+), window id (\d+)\b', log)}
    require(len(outputs) == 1, 'Expected exactly one compositor-logged X11 output')
    actual_width, actual_height, window = next(iter(outputs))
    require((actual_width, actual_height) == (width, height) and window > 0,
            'Compositor-logged output geometry/ID mismatch')
    return window


def verify_window(log, tree, info, width, height, require_viewable=True):
    window = logged_window(log, width, height)
    tree_ids = {int(value, 16) for value in re.findall(r'^\s*(0x[0-9a-fA-F]+)\s', tree, re.MULTILINE)}
    require(window in tree_ids, 'Logged input window is absent from owned X root tree')
    identity = re.search(r'xwininfo: Window id: (0x[0-9a-fA-F]+)\b', info)
    require(identity is not None and int(identity[1], 16) == window,
            'Inspected input window ID mismatch')
    for label, expected in [('Width', width), ('Height', height)]:
        match = re.search(r'^\s*' + label + r':\s*(\d+)\s*$', info, re.MULTILINE)
        require(match is not None and int(match[1]) == expected, 'Unexpected input window ' + label.lower())
    if require_viewable:
        require(re.search(r'^\s*Map State:\s*IsViewable\s*$', info, re.MULTILINE) is not None,
                'Logged input window is not viewable')
    return window


def marker(log, name, expected):
    matches = [json.loads(line[len(name) + 1:]) for line in log.splitlines()
               if line.startswith(name + ' ')]
    require(len(matches) == 1, f'Expected exactly one {name} marker')
    require(isinstance(matches[0], dict)
            and all(type(matches[0].get(k)) is type(v) and matches[0].get(k) == v
                for k, v in expected.items()), f'Failed {name} oracle: {matches[0]}')
    return matches[0]


def x11_window(log):
    record = marker(log, 'GPUI_X11_WINDOW', {})
    require(set(record) == {'pid', 'window', 'width', 'height'}
            and all(type(value) is int and value > 0 for value in record.values())
            and record['pid'] > 1, 'Invalid native X11 window marker')
    return record


def x11_protocols(properties):
    lines = [line for line in properties.splitlines() if line.startswith('WM_PROTOCOLS')]
    require(len(lines) == 1, 'Expected exactly one X11 WM_PROTOCOLS property')
    # xprop has a built-in display format for this ICCCM property. Its default
    # is "WM_PROTOCOLS(ATOM): protocols  ...", whereas the generic atom-list
    # format uses "WM_PROTOCOLS(ATOM) = ...". Compare whole comma-separated
    # atom names, never a substring such as NOT_WM_DELETE_WINDOW.
    match = re.fullmatch(r'WM_PROTOCOLS\(ATOM\)(?:[ \t]*=[ \t]*|:[ \t]*protocols[ \t]+)(.*)', lines[0])
    require(match is not None, 'Invalid X11 WM_PROTOCOLS property format')
    atoms = [atom.strip(' \t') for atom in match[1].split(',')]
    require(all(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', atom) for atom in atoms),
            'Invalid X11 WM_PROTOCOLS atom list')
    return set(atoms)


def verify_x11_window(record, tree, info, properties, descendants, width, height):
    require(record['pid'] in descendants, 'X11 window PID is not an owned GUI descendant')
    pid = re.search(r'^_NET_WM_PID\(CARDINAL\) = (\d+)\s*$', properties, re.MULTILINE)
    require(pid is not None and int(pid[1]) == record['pid'], 'X11 window PID property mismatch')
    require('WM_DELETE_WINDOW' in x11_protocols(properties),
            'X11 window does not advertise WM_DELETE_WINDOW')
    # Reuse the strict root-tree, identity, geometry and viewability oracle.
    synthetic_log = f'x11 output {width}x{height}, window id {record["window"]}\n'
    return verify_window(synthetic_log, tree, info, width, height)


def x11_presented(log, window, width, height):
    records = [json.loads(line.removeprefix('GPUI_X11_FRAME ')) for line in log.splitlines()
               if line.startswith('GPUI_X11_FRAME ') and line.endswith('}')]
    for record in records:
        require(isinstance(record, dict) and set(record) == {'window', 'width', 'height'}
                and all(type(value) is int and value > 0 for value in record.values()),
                'Invalid native X11 frame marker')
    return any(record == {'window': window, 'width': width, 'height': height} for record in records)


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
                        XDG_CACHE_HOME=str(output / 'cache'), DSH_DESKTOP_BACKEND='wayland')
        self.expected_text = EXPECTED_TEXT
        self.window = None

    def launch(self, args, label, env=None, input_text=None):
        log = self.output / (label + '.log')
        stream = log.open('wb')
        self.streams.append(stream)
        process = subprocess.Popen(args, cwd=self.output, env=env or self.env,
                                   stdout=stream, stderr=subprocess.STDOUT,
                                   stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
                                   start_new_session=True)
        self.processes.append(process)
        if input_text is not None:
            process.stdin.write(input_text.encode('utf-8'))
            process.stdin.close()
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
        self.xvfb = xvfb
        return {'private_display': self.env['DISPLAY'], 'inherited_display_excluded': inherited}

    def compositor(self, shell, label, width=WIDTH, height=HEIGHT, input_enabled=False):
        socket = label
        config = self.output / (label + '-weston.ini')
        config.write_text(WESTON_CONFIG)
        help_text = self.command(['weston', '--help'], check=False)
        # Legacy X11 Weston defaults to GL (its --use-gl flag is headless-only).
        renderer = ['--renderer=gl'] if '--renderer' in help_text.stdout + help_text.stderr else []
        weston, _ = self.launch(['weston', '--backend=x11-backend.so', *renderer,
                                '--shell=' + shell + '-shell.so', '--socket=' + socket,
                                f'--width={width}', f'--height={height}', '--idle-time=0',
                                '--config=' + str(config), '--log=' + str(self.output / (label + '-weston.log'))], label)
        def ready():
            require(weston.poll() is None, 'Owned Weston exited; inspect compositor logs')
            return (self.runtime / socket).exists()
        wait_for(ready, 15, 'owned Weston socket')
        self.env['WAYLAND_DISPLAY'] = socket
        if input_enabled:
            def discover():
                require(weston.poll() is None, 'Owned Weston exited during window discovery')
                log = (self.output / (label + '-weston.log')).read_text(errors='replace')
                tree = self.command(['xwininfo', '-root', '-tree'], check=False)
                diagnostics = {'monotonic': time.monotonic(), 'compositor_pid': weston.pid,
                               'display': self.env['DISPLAY'], 'compositor_log': log,
                               'tree': {'stdout': tree.stdout, 'stderr': tree.stderr,
                                        'returncode': tree.returncode}}
                candidate = None
                try:
                    candidate = logged_window(log, width, height)
                    info = self.command(['xwininfo', '-id', str(candidate)], check=False)
                    diagnostics['window'] = {'id': candidate, 'stdout': info.stdout,
                                             'stderr': info.stderr, 'returncode': info.returncode}
                    require(tree.returncode == 0 and info.returncode == 0,
                            'Private X window inspection failed')
                    require(weston.poll() is None, 'Owned Weston exited during window inspection')
                    candidate = verify_window(log, tree.stdout, info.stdout, width, height, require_viewable=False)
                    diagnostics['verified'] = True
                except RuntimeError as error:
                    diagnostics['error'] = str(error)
                    candidate = None
                # Preserve all observations, including transient unmapped windows
                # and the final successful ID; never depend on window-title uniqueness.
                with (self.output / (label + '-window-discovery.jsonl')).open('a') as stream:
                    stream.write(json.dumps(diagnostics) + '\n')
                require(weston.poll() is None, 'Owned Weston exited during window discovery')
                return candidate
            self.window = wait_for(discover, 15, 'verified private Weston X window')
            self.input_compositor = weston
            self.input_compositor_log = self.output / (label + '-weston.log')
        return weston

    def input_click(self, coordinates, first):
        # Weston may defer mapping until its first client/frame. Discovery need
        # not wait for that, but no OS input is allowed until mapping is proven.
        require(self.input_compositor.poll() is None, 'Owned input compositor exited')
        log = self.input_compositor_log.read_text(errors='replace')
        tree = self.command(['xwininfo', '-root', '-tree'])
        info = self.command(['xwininfo', '-id', str(self.window)])
        diagnostics = {'window': self.window, 'tree': tree.stdout, 'info': info.stdout}
        with (self.output / 'input-window-verification.jsonl').open('a') as stream:
            stream.write(json.dumps(diagnostics) + '\n')
        require(verify_window(log, tree.stdout, info.stdout, WIDTH, HEIGHT) == self.window,
                'Input target changed since private compositor discovery')
        require(self.input_compositor.poll() is None, 'Owned input compositor exited')
        window = str(self.window)
        self.command(['xdotool', 'windowfocus', '--sync', window])
        require(self.command(['xdotool', 'getwindowfocus']).stdout.strip() == window,
                'Private Weston focus verification failed')
        def click(x, y):
            self.move_and_click(window, x, y)
        if first:
            click(400, 650)
            self.command(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'])
            self.command(['xdotool', 'type', '--clearmodifiers', '--delay', '20', '--', EXPECTED_TEXT])
        click(*coordinates)

    def move_and_click(self, window, x, y):
        require(0 <= x < WIDTH and 0 <= y < HEIGHT, 'Unsafe input coordinate')
        geometry = self.command(['xdotool', 'getwindowgeometry', '--shell', window]).stdout
        fields = dict(re.findall(r'^(WINDOW|X|Y|WIDTH|HEIGHT)=(-?\d+)$', geometry, re.MULTILINE))
        require(all(key in fields for key in ('WINDOW', 'X', 'Y', 'WIDTH', 'HEIGHT')),
                'Incomplete input window geometry')
        require(int(fields['WINDOW']) == int(window) and int(fields['WIDTH']) == WIDTH
                and int(fields['HEIGHT']) == HEIGHT, 'Input window geometry changed')
        target = (int(fields['X']) + x, int(fields['Y']) + y)
        # xdotool 3.x --sync waits for movement away from the old position,
        # including when the target already equals it. Send and Allow occupy
        # the same coordinates. Verify arrival instead of waiting for movement.
        # https://github.com/jordansissel/xdotool/blob/v3.20160805.1/cmd_mousemove.c#L206-L208
        self.command(['xdotool', 'mousemove', '--window', window, str(x), str(y)])
        def arrived():
            require(self.input_compositor.poll() is None, 'Owned input compositor exited')
            pointer = self.command(['xdotool', 'getmouselocation', '--shell']).stdout
            actual = dict(re.findall(r'^(X|Y|WINDOW)=(-?\d+)$', pointer, re.MULTILINE))
            require(all(key in actual for key in ('X', 'Y', 'WINDOW')), 'Incomplete pointer location')
            matched = ((int(actual['X']), int(actual['Y'])) == target
                       and int(actual['WINDOW']) == int(window))
            with (self.output / 'input-pointer-verification.jsonl').open('a') as stream:
                stream.write(json.dumps({'window': int(window), 'relative_target': [x, y],
                                         'root_target': target, 'pointer': actual, 'matched': matched}) + '\n')
            return matched
        wait_for(arrived, 2, 'pointer arrival in verified input window')
        require(self.command(['xdotool', 'getwindowfocus']).stdout.strip() == window,
                'Private input focus changed before click')
        # No --window here: xdotool click uses genuine XTest button events.
        self.command(['xdotool', 'click', '1'])

    def app(self, label, flags, extra_env=None):
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
            env.update(DSH_DESKTOP_EXTERNAL_INPUT='1', DSH_DESKTOP_E2E_TEXT=self.expected_text)
        if extra_env:
            env.update(extra_env)
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


class X11Harness(Harness):
    def __init__(self, binary, output, runtime):
        super().__init__(binary, output, runtime)
        self.env.update(DSH_DESKTOP_BACKEND='x11', XDG_SESSION_TYPE='x11')
        self.expected_text = X11_EXPECTED_TEXT
        self.clipboard_round_trips = 0

    def app(self, label, flags, extra_env=None):
        process, log, root, tmp = super().app(label, flags, extra_env)
        self.input_compositor = process  # Shared XTest helpers guard the owning app.
        self.app_log, self.app_label = log, label
        self.window_record = None
        return process, log, root, tmp

    def verify_app_window(self, width=WIDTH, height=HEIGHT):
        diagnostics = {'monotonic': time.monotonic(), 'display': self.env.get('DISPLAY'),
                       'app_pid': self.input_compositor.pid, 'expected_size': [width, height],
                       'app_log': str(self.app_log), 'verified': False}
        try:
            require(self.xvfb.poll() is None, 'Owned Xvfb exited')
            require(self.input_compositor.poll() is None, 'Owned X11 app exited')
            log = self.app_log.read_text(errors='replace')
            record = x11_window(log)
            diagnostics['window'] = record
            require((record['width'], record['height']) == (WIDTH, HEIGHT),
                    'Unexpected initial native X11 window dimensions')
            if self.window_record is not None:
                require(record == self.window_record, 'Native X11 window identity changed')
                require(same_process_running(record['pid'], self.window_process),
                        'Native X11 window process identity changed')
            descendants = process_tree(self.input_compositor.pid)
            diagnostics['owned_pids'] = list(descendants)
            window = str(record['window'])
            for name, command in [
                    ('tree', ['xwininfo', '-root', '-tree']),
                    ('info', ['xwininfo', '-id', window]),
                    ('properties', ['xprop', '-id', window, '_NET_WM_PID', 'WM_PROTOCOLS'])]:
                result = self.command(command, check=False)
                diagnostics[name] = {'stdout': result.stdout, 'stderr': result.stderr,
                                     'returncode': result.returncode}
                require(result.returncode == 0, 'Owned X11 window inspection failed: ' + name)
            verified = verify_x11_window(
                record, diagnostics['tree']['stdout'], diagnostics['info']['stdout'],
                diagnostics['properties']['stdout'], descendants, width, height)
            self.window_record = record
            self.window_process = descendants[record['pid']]
            self.window = verified
            diagnostics['verified'] = True
            return verified
        except Exception as error:
            diagnostics['error'] = str(error)
            raise
        finally:
            # Retain raw xprop/xwininfo output even when the parser, ownership
            # check or a command fails, rather than logging only successful IDs.
            with (self.output / (self.app_label + '-window-verification.jsonl')).open('a') as stream:
                stream.write(json.dumps(diagnostics) + '\n')

    def wait_frame(self, width=WIDTH, height=HEIGHT, offset=0):
        def ready():
            require(self.xvfb.poll() is None, 'Owned Xvfb exited')
            require(self.input_compositor.poll() is None, 'Owned X11 app exited before a frame')
            text = self.app_log.read_text(errors='replace')
            if not re.search(r'^GPUI_X11_WINDOW .*\n', text, re.MULTILINE):
                return False
            record = x11_window(text)
            if not x11_presented(text[offset:], record['window'], width, height):
                return False
            self.verify_app_window(width, height)
            return True
        wait_for(ready, 20, f'owned native X11 {width}x{height} frame')

    def focused(self):
        window = str(self.verify_app_window())
        self.command(['xdotool', 'windowfocus', '--sync', window])
        require(self.command(['xdotool', 'getwindowfocus']).stdout.strip() == window,
                'Native X11 app focus verification failed')
        return window

    def clipboard_matches(self, expected, phase):
        # This reader is used only after verification of our private Xvfb and
        # app window. Log the two fixed fixture values, never a user clipboard.
        require((phase, expected) in [('owner', CLIPBOARD_TEXT), ('round-trip', X11_EXPECTED_TEXT)],
                'Unexpected clipboard diagnostic fixture')
        diagnostics = {'monotonic': time.monotonic(), 'phase': phase,
                       'window': self.window, 'expected': expected,
                       'returncode': None, 'matched': False}
        def capture(actual, stderr):
            for name, value in [('actual', actual), ('stderr', stderr)]:
                if isinstance(value, bytes):
                    value = value.decode('utf-8', errors='replace')
                value = value or ''
                diagnostics[name] = value[:CLIPBOARD_DIAGNOSTIC_CHARACTERS]
                diagnostics[name + '_characters'] = len(value)
                diagnostics[name + '_truncated'] = len(value) > CLIPBOARD_DIAGNOSTIC_CHARACTERS
        try:
            result = self.command(['xclip', '-selection', 'clipboard', '-out', '-target', 'UTF8_STRING'],
                                  check=False)
            capture(result.stdout, result.stderr)
            diagnostics['returncode'] = result.returncode
            # Compare the full, unmodified output. Diagnostic truncation must
            # never turn an overlong or otherwise incorrect value into a pass.
            diagnostics['matched'] = result.returncode == 0 and result.stdout == expected
            return diagnostics['matched']
        except subprocess.TimeoutExpired as error:
            capture(error.stdout, error.stderr)
            diagnostics['timed_out'] = True
            diagnostics['error'] = str(error)
            raise
        except Exception as error:
            diagnostics['error'] = str(error)
            raise
        finally:
            # Both callers have bounded five-second polling loops. Preserve
            # every bounded observation, including the one before a failure.
            with (self.output / (self.app_label + '-clipboard-verification.jsonl')).open('a') as stream:
                stream.write(json.dumps(diagnostics) + '\n')

    def input_click(self, coordinates, first):
        self.wait_frame()
        window = self.focused()
        if first:
            self.move_and_click(window, 400, 650)
            clipboard, _ = self.launch(
                ['xclip', '-quiet', '-selection', 'clipboard', '-in', '-target', 'UTF8_STRING'],
                self.app_label + '-clipboard-owner', input_text=CLIPBOARD_TEXT)
            def clipboard_owned():
                require(clipboard.poll() is None, 'Private clipboard owner exited early')
                return self.clipboard_matches(CLIPBOARD_TEXT, 'owner')
            wait_for(clipboard_owned, 5, 'private UTF-8 clipboard owner')
            self.command(['xdotool', 'key', '--clearmodifiers', 'ctrl+a', 'ctrl+v'])
            self.command(['xdotool', 'type', '--clearmodifiers', '--delay', '20', '--', ' via Linux keyboard'])
            self.command(['xdotool', 'key', '--clearmodifiers', 'ctrl+a', 'ctrl+c'])
            def copied():
                require(self.input_compositor.poll() is None, 'Owned X11 app exited during clipboard test')
                return self.clipboard_matches(self.expected_text, 'round-trip')
            wait_for(copied, 5, 'native X11 UTF-8 clipboard round-trip')
            self.clipboard_round_trips += 1
            self.focused()
        self.move_and_click(window, *coordinates)

    def external_lifecycle(self):
        app, log, _, tmp = self.app('external-lifecycle', [])
        self.wait_frame()
        window = self.verify_app_window()
        width, height = WIDTH + 60, HEIGHT + 40
        offset = len(log.read_text(errors='replace'))
        self.command(['xdotool', 'windowsize', '--sync', str(window), str(width), str(height)])
        self.wait_frame(width, height, offset)
        # Verify exact owned PID, window, geometry and WM protocol again before
        # sending the real window-manager close request to this specific XID.
        require(self.verify_app_window(width, height) == window, 'Close target changed')
        self.command([sys.executable, '-c', X11_CLOSE_HELPER, str(window)])
        app.wait(timeout=20)
        require(app.returncode == 0, f'WM_DELETE_WINDOW exited {app.returncode}, expected clean shutdown')
        tree = self.command(['xwininfo', '-root', '-tree']).stdout
        tree_ids = {int(value, 16) for value in re.findall(r'^\s*(0x[0-9a-fA-F]+)\s', tree, re.MULTILINE)}
        require(window not in tree_ids, 'Closed native X11 window remains in the owned root tree')
        self.clean_payload(tmp)
        return {'os_resize': [width, height], 'resized_frame': True,
                'wm_delete_window': True, 'window_destroyed': True,
                'returncode': app.returncode, 'payload_cleanup': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path, help='packaged raw dsh ELF')
    parser.add_argument('output', nargs='?', type=Path, help='fresh artifact directory')
    parser.add_argument('--backend', choices=('wayland', 'x11'), default='wayland',
                        help='native display backend to qualify (default: wayland)')
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
              'backend': args.backend,
              'input_route': ('xdotool XTest -> authenticated private Xvfb -> native GPUI X11'
                              if args.backend == 'x11' else
                              'xdotool XTest -> authenticated private Xvfb -> Weston -> GPUI Wayland')}
    harness = None
    try:
        for tool in ['Xvfb', 'xdotool', 'xwininfo', 'xdpyinfo'] + (
                ['xprop', 'xclip'] if args.backend == 'x11' else ['weston']):
            require(shutil.which(tool), 'Missing required tool: ' + tool)
        with tempfile.TemporaryDirectory(prefix='dsh-gui-', dir='/tmp') as runtime:
            Path(runtime).chmod(0o700)
            harness_class = X11Harness if args.backend == 'x11' else Harness
            harness = harness_class(binary, output, Path(runtime))
            try:
                result.update(harness.start_display())
                input_compositor = (harness.compositor('desktop', 'composition', input_enabled=True)
                                    if args.backend == 'wayland' else None)
                # Auto must prefer Wayland when both endpoints exist, and use
                # native X11 when only DISPLAY exists. Later cases are explicit.
                choice = {'DSH_DESKTOP_BACKEND': 'auto'}
                app, log, root, tmp = harness.app('demo', ['--offline-e2e'], choice)
                text, clicks = harness.run_until_exit(app, log, input_enabled=True)
                if args.backend == 'wayland':
                    require_text_input_manager(text)
                require(clicks == 2, f'Expected two native clicks, saw {clicks}')
                result['demo'] = marker(text, 'DSH_DESKTOP_DEMO', {
                    'native_events': True, 'tool_approval': 'approved', 'completed': True,
                    'workspace_write': True, 'reload': 'passed', 'japanese_frame': 'passed',
                    'ime_composition': args.backend == 'wayland'})
                require((root / 'workspace/native-demo.txt').read_text() == 'durable native tool result',
                        'Durable workspace write mismatch')
                result['frames'] = {name: ppm_info(root / name) for name in [
                    'transcript.ppm.initial.ppm', 'transcript.ppm', 'transcript.ppm.settings.ppm']}
                harness.clean_payload(tmp)
                result['input_requests'] = clicks
                result['auto_selected_backend'] = args.backend
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
                if input_compositor is not None:
                    harness.stop(input_compositor)
                    # Give lifecycle resize requests room beyond the initial app size.
                    harness.compositor('desktop', 'lifecycle', width=1280, height=900)
                # Explicit X11 must ignore even an unusable Wayland endpoint.
                choice = {'WAYLAND_DISPLAY': 'not-a-real-wayland-socket'} if args.backend == 'x11' else None
                app, log, _, tmp = harness.app('lifecycle', ['--smoke'], choice)
                text, _ = harness.run_until_exit(app, log)
                result['lifecycle'] = marker(text, 'DSH_DESKTOP_SMOKE', {
                    'frame': True, 'resized': True, 'close_requested': True, 'destroyed': True})
                harness.clean_payload(tmp)
                if args.backend == 'x11':
                    require(harness.clipboard_round_trips == 2, 'Missing native X11 clipboard coverage')
                    result['clipboard'] = {'utf8_external_read': True, 'utf8_external_write': True,
                                           'round_trips': harness.clipboard_round_trips}
                    result['external_lifecycle'] = harness.external_lifecycle()
                app, log, _, tmp = harness.app('term', [])
                wait_for(lambda: list(tmp.iterdir()) or app.poll() is not None, 15, 'extracted running GUI')
                def idle_frame():
                    require(app.poll() is None, 'Idle GUI exited before presenting a frame')
                    return re.search(r'wl_callback(?:@|#)\d+\.done\(', log.read_text(errors='replace'))
                if args.backend == 'x11':
                    harness.wait_frame()
                else:
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
