#!/usr/bin/env python3
"""Pure harness tests; no GUI claims and no access to any desktop."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('smoke', Path(__file__).with_name('smoke-release-linux.py'))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class ProtocolTests(unittest.TestCase):
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
