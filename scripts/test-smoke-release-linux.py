#!/usr/bin/env python3
"""Pure harness tests; no GUI claims and no access to any desktop."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('smoke', Path(__file__).with_name('smoke-release-linux.py'))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class ProtocolTests(unittest.TestCase):
    def test_native_x11_window_requires_owned_pid_and_exact_window(self):
        record = {'pid': 321, 'window': 2097157, 'width': 1120, 'height': 760}
        log = 'GPUI_X11_WINDOW ' + json.dumps(record) + '\n'
        tree = '  0x200005 "dsh": () 1120x760+0+0\n  0x200006 "dsh": () 1120x760+0+0\n'
        info = 'xwininfo: Window id: 0x200005 "dsh"\n  Width: 1120\n  Height: 760\n  Map State: IsViewable\n'
        properties = '_NET_WM_PID(CARDINAL) = 321\nWM_PROTOCOLS(ATOM) = WM_DELETE_WINDOW\n'
        self.assertEqual(smoke.x11_window(log), record)
        self.assertEqual(smoke.verify_x11_window(record, tree, info, properties, {321: {}}, 1120, 760), 2097157)
        for candidate_tree, candidate_info, candidate_properties, descendants in [
                (tree, info, properties, {322: {}}),
                (tree, info, properties.replace('321', '322'), {321: {}}),
                (tree, info, properties.replace('WM_DELETE_WINDOW', 'WM_TAKE_FOCUS'), {321: {}}),
                (tree.replace('0x200005', '0x300005'), info, properties, {321: {}}),
                (tree, info.replace('0x200005', '0x200006'), properties, {321: {}}),
                (tree, info.replace('IsViewable', 'IsUnMapped'), properties, {321: {}})]:
            with self.subTest(descendants=descendants, properties=candidate_properties), self.assertRaises(RuntimeError):
                smoke.verify_x11_window(record, candidate_tree, candidate_info,
                                        candidate_properties, descendants, 1120, 760)

    def test_native_x11_window_marker_rejects_ambiguous_or_invalid_ids(self):
        record = {'pid': 321, 'window': 2097157, 'width': 1120, 'height': 760}
        good = 'GPUI_X11_WINDOW ' + json.dumps(record) + '\n'
        for log in ['', good + good, 'GPUI_X11_WINDOW []\n',
                    'GPUI_X11_WINDOW ' + json.dumps(dict(record, window=True)),
                    'GPUI_X11_WINDOW ' + json.dumps(dict(record, pid=1)),
                    'GPUI_X11_WINDOW ' + json.dumps(dict(record, window=-1)),
                    'GPUI_X11_WINDOW ' + json.dumps(dict(record, width='1120')),
                    'GPUI_X11_WINDOW ' + json.dumps(dict(record, extra=1))]:
            with self.subTest(log=log), self.assertRaises(RuntimeError):
                smoke.x11_window(log)

    def test_native_x11_frame_matches_window_and_requested_size(self):
        frame = 'GPUI_X11_FRAME {"window":2097157,"width":1120,"height":760}\n'
        self.assertTrue(smoke.x11_presented(frame, 2097157, 1120, 760))
        self.assertFalse(smoke.x11_presented(frame, 2097158, 1120, 760))
        self.assertFalse(smoke.x11_presented(frame, 2097157, 1180, 800))
        self.assertFalse(smoke.x11_presented('GPUI_X11_FRAME {"window":2097157', 2097157, 1120, 760))
        for value in [{'window': True, 'width': 1120, 'height': 760},
                      {'window': 2097157, 'width': 0, 'height': 760},
                      {'window': 2097157, 'width': 1120, 'height': '760'},
                      {'window': 2097157}, {'window': 2097157, 'width': 1120, 'height': 760, 'extra': 1}]:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                smoke.x11_presented('GPUI_X11_FRAME ' + json.dumps(value), 2097157, 1120, 760)

    def test_native_x11_fixture_excludes_inherited_desktop_and_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runtime = base / 'runtime'
            runtime.mkdir()
            inherited = {'DISPLAY': ':0', 'XAUTHORITY': '/home/user/.Xauthority',
                         'WAYLAND_DISPLAY': 'wayland-0', 'WAYLAND_SOCKET': '7',
                         'DSH_DESKTOP_BACKEND': 'wayland', 'GPUI_NATIVE_E2E': '0',
                         'OPENAI_API_KEY': 'not-real', 'DEEPSEEK_API_KEY': 'not-real'}
            with mock.patch.dict(os.environ, inherited):
                harness = smoke.X11Harness(base / 'packaged', base, runtime)
            for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'OPENAI_API_KEY', 'DEEPSEEK_API_KEY'):
                self.assertNotIn(key, harness.env)
            self.assertEqual(harness.env['XAUTHORITY'], str(runtime / 'Xauthority'))
            self.assertEqual(harness.env['DSH_DESKTOP_BACKEND'], 'x11')
            self.assertEqual(harness.env['XDG_SESSION_TYPE'], 'x11')
            harness.env['DISPLAY'] = ':12345'
            with mock.patch.object(harness, 'launch', return_value=(mock.sentinel.process, base / 'app.log')) as launch:
                harness.app('fixture', ['--offline-e2e'], {'DSH_DESKTOP_BACKEND': 'auto'})
            environment = launch.call_args.args[2]
            self.assertEqual(environment['DISPLAY'], ':12345')
            self.assertEqual(environment['DSH_DESKTOP_BACKEND'], 'auto')
            self.assertEqual(environment['DSH_DESKTOP_E2E_TEXT'], smoke.X11_EXPECTED_TEXT)
            self.assertEqual(environment['DSH_DESKTOP_EXTERNAL_INPUT'], '1')
            self.assertNotIn('WAYLAND_DISPLAY', environment)
            self.assertNotIn('WAYLAND_SOCKET', environment)

    def test_native_x11_clipboard_uses_external_owner_and_real_input(self):
        harness = smoke.X11Harness.__new__(smoke.X11Harness)
        harness.expected_text = smoke.X11_EXPECTED_TEXT
        harness.app_label = 'fixture'
        harness.clipboard_round_trips = 0
        harness.input_compositor = mock.Mock()
        harness.input_compositor.poll.return_value = None
        owner = mock.Mock()
        owner.poll.return_value = None
        reads = iter([smoke.CLIPBOARD_TEXT, smoke.X11_EXPECTED_TEXT])
        def command(args, check=True):
            return mock.Mock(stdout=next(reads) if args[0] == 'xclip' else '', returncode=0)
        with mock.patch.object(harness, 'wait_frame'), \
             mock.patch.object(harness, 'focused', return_value='2097157'), \
             mock.patch.object(harness, 'move_and_click') as click, \
             mock.patch.object(harness, 'launch', return_value=(owner, None)) as launch, \
             mock.patch.object(harness, 'command', side_effect=command) as invoke:
            harness.input_click((1032, 725), True)
        self.assertEqual(harness.clipboard_round_trips, 1)
        launch.assert_called_once_with(
            ['xclip', '-quiet', '-selection', 'clipboard', '-in', '-target', 'UTF8_STRING'],
            'fixture-clipboard-owner', input_text=smoke.CLIPBOARD_TEXT)
        self.assertEqual(click.call_args_list, [mock.call('2097157', 400, 650), mock.call('2097157', 1032, 725)])
        calls = [call.args[0] for call in invoke.call_args_list]
        self.assertIn(['xdotool', 'key', '--clearmodifiers', 'ctrl+a', 'ctrl+v'], calls)
        self.assertIn(['xdotool', 'key', '--clearmodifiers', 'ctrl+a', 'ctrl+c'], calls)
        self.assertIn(['xdotool', 'type', '--clearmodifiers', '--delay', '20', '--', ' via Linux keyboard'], calls)
        self.assertFalse(any('--window' in command for command in calls))

    def test_native_x11_clipboard_mismatch_prevents_submit(self):
        harness = smoke.X11Harness.__new__(smoke.X11Harness)
        harness.expected_text = smoke.X11_EXPECTED_TEXT
        harness.app_label = 'fixture'
        harness.clipboard_round_trips = 0
        harness.input_compositor = mock.Mock()
        harness.input_compositor.poll.return_value = None
        owner = mock.Mock()
        owner.poll.return_value = None
        def bounded_check(predicate, timeout, label):
            if not predicate():
                raise RuntimeError('Timed out waiting for ' + label)
        with mock.patch.object(harness, 'wait_frame'), \
             mock.patch.object(harness, 'focused', return_value='2097157'), \
             mock.patch.object(harness, 'move_and_click') as click, \
             mock.patch.object(harness, 'launch', return_value=(owner, None)), \
             mock.patch.object(harness, 'command', return_value=mock.Mock(stdout=smoke.CLIPBOARD_TEXT, returncode=0)), \
             mock.patch.object(smoke, 'wait_for', side_effect=bounded_check), \
             self.assertRaisesRegex(RuntimeError, 'clipboard round-trip'):
            harness.input_click((1032, 725), True)
        click.assert_called_once_with('2097157', 400, 650)
        self.assertEqual(harness.clipboard_round_trips, 0)

    def test_native_x11_close_sends_window_protocol_instead_of_destroying(self):
        import ctypes
        xlib = mock.Mock()
        xlib.XOpenDisplay.return_value = 100
        xlib.XInternAtom.side_effect = [40, 41]
        def send(display, window, propagate, event_mask, event):
            self.assertEqual((display, window, propagate, event_mask), (100, 2097157, 0, 0))
            client = event._obj.client
            self.assertEqual((client.type, client.window, client.message_type, client.format), (33, 2097157, 40, 32))
            self.assertEqual(list(client.data.l), [41, 0, 0, 0, 0])
            self.assertEqual(ctypes.sizeof(event._obj), 24 * ctypes.sizeof(ctypes.c_long))
            return 1
        xlib.XSendEvent.side_effect = send
        with mock.patch.object(ctypes, 'CDLL', return_value=xlib), \
             mock.patch.dict(os.environ, {'DISPLAY': ':12345'}), \
             mock.patch.object(sys, 'argv', ['helper', '2097157']):
            exec(compile(smoke.X11_CLOSE_HELPER, '<x11-close-helper>', 'exec'), {})
        xlib.XOpenDisplay.assert_called_once_with(b':12345')
        xlib.XSendEvent.assert_called_once()
        xlib.XSync.assert_called_once_with(100, 0)
        xlib.XCloseDisplay.assert_called_once_with(100)
        xlib.XDestroyWindow.assert_not_called()

    def test_native_x11_external_resize_requires_new_present_then_clean_close(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'app.log'
            log.write_text('initial frame\n')
            app = mock.Mock(returncode=0)
            harness = smoke.X11Harness.__new__(smoke.X11Harness)
            with mock.patch.object(harness, 'app', return_value=(app, log, root, root)) as launch, \
                 mock.patch.object(harness, 'wait_frame') as frame, \
                 mock.patch.object(harness, 'verify_app_window', return_value=2097157), \
                 mock.patch.object(harness, 'command', return_value=mock.Mock(stdout='')) as invoke, \
                 mock.patch.object(harness, 'clean_payload') as clean:
                result = harness.external_lifecycle()
            launch.assert_called_once_with('external-lifecycle', [])
            self.assertEqual(frame.call_args_list, [mock.call(), mock.call(1180, 800, len('initial frame\n'))])
            calls = [call.args[0] for call in invoke.call_args_list]
            self.assertEqual(calls, [
                ['xdotool', 'windowsize', '--sync', '2097157', '1180', '800'],
                [sys.executable, '-c', smoke.X11_CLOSE_HELPER, '2097157'],
                ['xwininfo', '-root', '-tree']])
            self.assertTrue(result['window_destroyed'])
            self.assertEqual(result['os_resize'], [1180, 800])
            clean.assert_called_once_with(root)

    def test_native_x11_external_resize_failure_never_sends_close(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'app.log'
            log.write_text('initial frame\n')
            harness = smoke.X11Harness.__new__(smoke.X11Harness)
            with mock.patch.object(harness, 'app', return_value=(mock.Mock(), log, root, root)), \
                 mock.patch.object(harness, 'wait_frame', side_effect=[None, RuntimeError('no resized frame')]), \
                 mock.patch.object(harness, 'verify_app_window', return_value=2097157), \
                 mock.patch.object(harness, 'command') as invoke, \
                 self.assertRaisesRegex(RuntimeError, 'no resized frame'):
                harness.external_lifecycle()
            invoke.assert_called_once_with(['xdotool', 'windowsize', '--sync', '2097157', '1180', '800'])

    def test_native_x11_reused_pid_is_rejected_before_display_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            record = {'pid': 321, 'window': 2097157, 'width': 1120, 'height': 760}
            harness = smoke.X11Harness.__new__(smoke.X11Harness)
            harness.xvfb = mock.Mock()
            harness.xvfb.poll.return_value = None
            harness.input_compositor = mock.Mock()
            harness.input_compositor.poll.return_value = None
            harness.app_log = root / 'app.log'
            harness.app_log.write_text('GPUI_X11_WINDOW ' + json.dumps(record) + '\n')
            harness.window_record = record
            harness.window_process = {'starttime': '100'}
            with mock.patch.object(smoke, 'same_process_running', return_value=False), \
                 mock.patch.object(harness, 'command') as invoke, \
                 self.assertRaisesRegex(RuntimeError, 'process identity changed'):
                harness.verify_app_window()
            invoke.assert_not_called()

    def test_window_selected_by_owned_log_id_despite_duplicate_titles(self):
        log = '[07:04:18.911] x11 output 1120x760, window id 2097157\n'
        tree = ('     0x200005 "Weston Compositor": () 1120x760+0+0\n'
                '     0x200006 "Weston Compositor": () 1120x760+0+0\n')
        info = ('xwininfo: Window id: 0x200005 "Weston Compositor"\n'
                '  Width: 1120\n  Height: 760\n  Map State: IsViewable\n')
        self.assertEqual(smoke.verify_window(log, tree, info, 1120, 760), 2097157)
        unmapped = info.replace('IsViewable', 'IsUnMapped')
        self.assertEqual(smoke.verify_window(log, tree, unmapped, 1120, 760,
                                            require_viewable=False), 2097157)
        with self.assertRaises(RuntimeError):
            smoke.verify_window(log, tree, unmapped, 1120, 760)
        self.assertEqual(smoke.verify_window(log, tree.replace('Weston Compositor', 'arbitrary title'),
                                           info.replace('Weston Compositor', 'arbitrary title'), 1120, 760), 2097157)

    def test_window_rejects_missing_or_mismatched_evidence(self):
        log = 'x11 output 1120x760, window id 2097157\n'
        tree = '  0x200005 "Weston Compositor": () 1120x760+0+0\n'
        info = 'xwininfo: Window id: 0x200005 "Weston Compositor"\n  Width: 1120\n  Height: 760\n  Map State: IsViewable\n'
        cases = [('', tree, info),
                 (log + 'x11 output 1120x760, window id 2097158\n', tree, info),
                 (log.replace('1120x760', '1280x900'), tree, info),
                 (log, tree.replace('0x200005', '0x200006'), info),
                 (log, tree, info.replace('0x200005', '0x200006')),
                 (log, tree, info.replace('Width: 1120', 'Width: 1119')),
                 (log, tree, info.replace('Height: 760', 'Height: 759')),
                 (log, tree, info.replace('  Width: 1120\n', '')),
                 (log, tree, info.replace('IsViewable', 'IsUnMapped')),
                 (log, tree, info.replace('  Map State: IsViewable\n', ''))]
        for evidence in cases:
            with self.subTest(evidence=evidence), self.assertRaises(RuntimeError):
                smoke.verify_window(*evidence, 1120, 760)

    def test_repeated_position_still_sends_two_real_clicks_without_sync(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = smoke.Harness.__new__(smoke.Harness)
            harness.output = Path(directory)
            harness.input_compositor = mock.Mock()
            harness.input_compositor.poll.return_value = None
            geometry = 'WINDOW=2097157\nX=20\nY=30\nWIDTH=1120\nHEIGHT=760\n'
            pointer = 'X=1052\nY=755\nSCREEN=0\nWINDOW=2097157\n'
            def command(args):
                if args[1] == 'getwindowgeometry':
                    return mock.Mock(stdout=geometry)
                if args[1] == 'getmouselocation':
                    return mock.Mock(stdout=pointer)
                if args[1] == 'getwindowfocus':
                    return mock.Mock(stdout='2097157\n')
                return mock.Mock(stdout='')
            with mock.patch.object(harness, 'command', side_effect=command) as invoke:
                harness.move_and_click('2097157', 1032, 725)
                harness.move_and_click('2097157', 1032, 725)
            calls = [call.args[0] for call in invoke.call_args_list]
            self.assertEqual(calls.count(['xdotool', 'click', '1']), 2)
            self.assertEqual(calls.count(['xdotool', 'mousemove', '--window', '2097157', '1032', '725']), 2)
            self.assertFalse(any('--sync' in command for command in calls))
            checks = [json.loads(line) for line in (harness.output / 'input-pointer-verification.jsonl').read_text().splitlines()]
            self.assertEqual(len(checks), 2)
            self.assertTrue(all(check['matched'] for check in checks))

    def test_pointer_mismatch_never_sends_click(self):
        with tempfile.TemporaryDirectory() as directory:
            for pointer in ['X=1031\nY=725\nWINDOW=2097157\n',
                            'X=1032\nY=725\nWINDOW=42\n']:
                harness = smoke.Harness.__new__(smoke.Harness)
                harness.output = Path(directory)
                harness.input_compositor = mock.Mock()
                harness.input_compositor.poll.return_value = None
                def command(args):
                    if args[1] == 'getwindowgeometry':
                        return mock.Mock(stdout='WINDOW=2097157\nX=0\nY=0\nWIDTH=1120\nHEIGHT=760\n')
                    return mock.Mock(stdout=pointer)
                def bounded_check(predicate, timeout, label):
                    self.assertEqual(timeout, 2)
                    self.assertFalse(predicate())
                    raise RuntimeError('Timed out waiting for ' + label)
                with mock.patch.object(harness, 'command', side_effect=command) as invoke, \
                     mock.patch.object(smoke, 'wait_for', side_effect=bounded_check), \
                     self.assertRaises(RuntimeError):
                    harness.move_and_click('2097157', 1032, 725)
                self.assertNotIn(mock.call(['xdotool', 'click', '1']), invoke.call_args_list)

    def test_click_bounds(self):
        self.assertEqual(smoke.parse_click('DSH_DESKTOP_INPUT {"x":1119.9,"y":759.9}'), (1119, 759))
        for x, y in [(-1, 4), (1120, 0), (0, 760), (True, 0), ('2', 0), (float('nan'), 0), (0, float('inf'))]:
            with self.subTest(x=x, y=y), self.assertRaises(RuntimeError):
                smoke.parse_click('DSH_DESKTOP_INPUT ' + json.dumps({'x': x, 'y': y}))
        for value in [{'x': 1}, {'x': 1, 'y': 2, 'command': 'bad'}, []]:
            with self.assertRaises(RuntimeError):
                smoke.parse_click('DSH_DESKTOP_INPUT ' + json.dumps(value))

    def test_marker_requires_exact_types_and_single_occurrence(self):
        good = 'DSH_DESKTOP_SMOKE {"frame":true}\n'
        self.assertEqual(smoke.marker(good, 'DSH_DESKTOP_SMOKE', {'frame': True}), {'frame': True})
        for text in ['', good + good, 'DSH_DESKTOP_SMOKE {"frame":1}']:
            with self.assertRaises(RuntimeError):
                smoke.marker(text, 'DSH_DESKTOP_SMOKE', {'frame': True})

    def test_ppm_payload_and_nonuniformity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'frame.ppm'
            path.write_bytes(b'P6\n2 1\n255\n' + bytes([10, 0, 255, 1, 2, 3]))
            self.assertEqual(smoke.ppm_info(path)['width'], 2)
            for value in [b'P6\n2 1\n255\n\0', b'P6\n2 1\n255\n' + b'\0' * 6, b'garbage']:
                path.write_bytes(value)
                with self.assertRaises(RuntimeError):
                    smoke.ppm_info(path)

    def test_app_fixture_creates_isolated_directories_and_options(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runtime = base / 'runtime'
            runtime.mkdir()
            harness = smoke.Harness(base / 'packaged-dsh', base, runtime)
            harness.env['WAYLAND_DISPLAY'] = 'owned-test-compositor'
            with mock.patch.object(harness, 'launch', return_value=(mock.sentinel.process, base / 'app.log')) as launch:
                process, log, root, tmp = harness.app('fixture', ['--offline-e2e'])
            self.assertIs(process, mock.sentinel.process)
            for name in ('workspace', 'data', 'tmp'):
                self.assertTrue((root / name).is_dir())
                self.assertEqual((root / name).stat().st_mode & 0o777, 0o700)
            command, label, environment = launch.call_args.args
            self.assertEqual(command, [str(base / 'packaged-dsh'), 'desktop', '--demo',
                '--data-dir', str(root / 'data'), '--workspace', str(root / 'workspace'),
                '--frame-output', str(root / 'transcript.ppm'), '--offline-e2e'])
            self.assertEqual(label, 'fixture-app')
            self.assertEqual(environment['TMPDIR'], str(tmp))
            self.assertEqual(environment['DSH_DESKTOP_EXTERNAL_INPUT'], '1')
            self.assertEqual(environment['DSH_DESKTOP_E2E_TEXT'], smoke.EXPECTED_TEXT)
            self.assertEqual(environment['WAYLAND_DISPLAY'], 'owned-test-compositor')
            self.assertNotIn('DSH_DESKTOP_EXTERNAL_INPUT', harness.env)

    def test_pending_pid_waits_for_complete_record(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pid'
            self.assertIsNone(smoke.pending_pid(path))
            for value in ['', '123']:
                path.write_text(value)
                self.assertIsNone(smoke.pending_pid(path))
            path.write_text('123\n')
            self.assertEqual(smoke.pending_pid(path), 123)
            for value in ['0\n', '1\n', 'abc\n', '123\n456\n']:
                path.write_text(value)
                with self.assertRaises(RuntimeError):
                    smoke.pending_pid(path)

    def test_cleanup_never_signals_reaped_process_group(self):
        harness = smoke.Harness.__new__(smoke.Harness)
        harness.owned_descendants, harness.streams = {}, []
        process = mock.Mock(pid=123)
        process.poll.return_value = 0
        harness.processes = [process]
        with mock.patch.object(smoke.os, 'killpg') as kill:
            harness.cleanup()
            kill.assert_not_called()

    def test_cleanup_handles_exit_after_timeout(self):
        harness = smoke.Harness.__new__(smoke.Harness)
        harness.owned_descendants, harness.streams = {}, []
        process = mock.Mock(pid=123)
        process.poll.side_effect = [None, 0]
        process.wait.side_effect = [smoke.subprocess.TimeoutExpired('fixture', 3), 0]
        harness.processes = [process]
        with mock.patch.object(smoke.os, 'killpg') as kill:
            harness.cleanup()
            kill.assert_called_once_with(123, smoke.signal.SIGTERM)

    def test_private_cookie_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'authority'
            smoke.auth_file(path, 1234, b'A' * 16)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIn(b'MIT-MAGIC-COOKIE-1', path.read_bytes())
            self.assertIn(b'1234', path.read_bytes())


if __name__ == '__main__':
    unittest.main()
