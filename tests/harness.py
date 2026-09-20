# ***************************************************************************
#                               Avoe - harness
#
#           Copyright (C) 2026 By Ulrik Hørlyk Hjort
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ***************************************************************************

"""Test helpers: drive bin/avoe in a pseudo-terminal or in batch mode."""

import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AVOE = os.path.join(ROOT, "bin", "avoe")
WORK = tempfile.mkdtemp(prefix="avoe-tests-")
EMPTY_HOME = tempfile.mkdtemp(prefix="avoe-home-")

_failures = 0
_passes = 0


def ctl(c):
    return bytes([ord(c) & 31])


def meta(c):
    return b"\x1b" + c.encode()


def path(name, content=None):
    """A file in the work directory, optionally (re)written with content."""
    p = os.path.join(WORK, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if content is None:
        if os.path.exists(p):
            os.remove(p)
    else:
        with open(p, "w") as f:
            f.write(content)
    return p


def read(p):
    with open(p) as f:
        return f.read()


def run(args, keys, rows=24, cols=80, env=None, delay=0.08, splash=False):
    """Run avoe in a pty, typing keys (b"" entries just wait).
    Returns (exit code or None if it had to be killed, screen output)."""
    if env is None:
        env = dict(os.environ, HOME=EMPTY_HOME)
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(AVOE, [AVOE] + ([] if splash else ["--no-splash"]) + list(args), env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    out = b""

    def pump(t):
        nonlocal out
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.02)
            if r:
                try:
                    out += os.read(fd, 65536)
                except OSError:
                    return

    pump(0.3)
    for k in keys:
        if k:
            os.write(fd, k)
        pump(delay)
    for _ in range(40):
        p, status = os.waitpid(pid, os.WNOHANG)
        if p:
            return os.waitstatus_to_exitcode(status), out
        pump(0.05)
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    return None, out


def batch(script, files=()):
    """Run a script with avoe --batch; returns (exit code, stdout, stderr)."""
    p = path("batch_script.avoe", script)
    r = subprocess.run([AVOE, "--batch", p] + list(files),
                       capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout, r.stderr


def check(name, cond, extra=""):
    global _failures, _passes
    if cond:
        _passes += 1
        print("PASS", name)
    else:
        _failures += 1
        print("FAIL", name, extra)


def finish():
    print("%d passed, %d failed" % (_passes, _failures))
    sys.exit(1 if _failures else 0)
