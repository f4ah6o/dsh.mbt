#!/usr/bin/env python3
"""Link the native Linux desktop against distro text/rendering libraries."""
import os
import shlex
import subprocess
import sys

compiler = shlex.split(os.environ.get('CC', 'cc'))
packages = ['x11', 'wayland-client', 'wayland-cursor', 'wayland-egl', 'egl', 'glesv2',
            'xkbcommon', 'pangoft2', 'fontconfig']
try:
    flags = shlex.split(subprocess.check_output(
        [os.environ.get('PKG_CONFIG', 'pkg-config'), '--cflags', '--libs', *packages],
        text=True))
except (OSError, subprocess.CalledProcessError):
    sys.exit('Install the Linux desktop development dependencies listed in README.md.')
sys.exit(subprocess.call([*compiler, *shlex.split(os.environ.get('CPPFLAGS', '')),
    *sys.argv[1:], *shlex.split(os.environ.get('CFLAGS', '')),
    *shlex.split(os.environ.get('LDFLAGS', '')), *flags]))
