# ***************************************************************************
#                              Avoe - test_fuzz
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

"""Short, repeatable fuzzing: mutated scripts and random keys must never
cause an internal error, a crash or a hang.  (Longer runs with other seeds
found real bugs; these seeds keep them from coming back.)"""

import fcntl
import glob
import os
import pty
import random
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

from harness import check, finish, ROOT, AVOE

BAD = ("Internal error", ".adb:", "check failed", "_ERROR", "stack overflow", "fatal")

sandbox = tempfile.mkdtemp(prefix="avoe-fuzz-")
home = os.path.join(sandbox, "home")
empty_bin = os.path.join(sandbox, "bin")   # PATH without programs: random shell commands cannot run
os.makedirs(home)
os.makedirs(empty_bin)
ENV = {"HOME": home, "PATH": empty_bin, "TERM": "xterm", "LANG": "C.UTF-8"}
ERROR_LOG = os.path.join(home, ".local", "state", "avoe", "internal-errors.log")

# ---------------------------------------------------------------------------
# Mutated scripts

corpus = [open(f, encoding="utf-8").read()
          for f in glob.glob(os.path.join(ROOT, "share/avoe/*.avoe")) + [os.path.join(ROOT, "examples/avoerc.avoe")]]
corpus += re.findall(r"```ada\n(.*?)```", open(os.path.join(ROOT, "docs/avoe-script.md"), encoding="utf-8").read(), re.S)
TOKEN = r"\w+|:=|=>|\.\.|\*\*|/=|<=|>=|\s+|\S"
tokens = sorted({t for c in corpus for t in re.findall(TOKEN, c) if not t.isspace()})


def mutate(rnd, source):
    parts = re.findall(TOKEN, source)
    for _ in range(rnd.randint(1, 6)):
        if not parts:
            break
        i = rnd.randrange(len(parts))
        op = rnd.random()
        if op < 0.3:
            del parts[i]
        elif op < 0.6:
            parts.insert(i, rnd.choice(tokens) + " ")
        elif op < 0.8:
            parts[i] = rnd.choice(tokens)
        else:
            j = rnd.randrange(len(parts))
            parts[i], parts[j] = parts[j], parts[i]
    return "".join(parts)


rnd = random.Random(2026)
bad = []
timeouts = 0
script = os.path.join(sandbox, "fuzz.avoe")
text_file = os.path.join(sandbox, "text.txt")
for n in range(250):
    source = mutate(rnd, rnd.choice(corpus))
    with open(script, "w", encoding="utf-8") as f:
        f.write(source)
    with open(text_file, "w") as f:
        f.write("hello world\nsecond line\n")
    try:
        r = subprocess.run([AVOE, "--batch", script, text_file], capture_output=True, text=True,
                           errors="replace", timeout=5, cwd=sandbox, env=ENV)
    except subprocess.TimeoutExpired:
        timeouts += 1          # A mutated script may simply loop for ever
        continue
    if r.returncode not in (0, 1) or any(s in r.stdout + r.stderr for s in BAD):
        bad.append((n, r.returncode, (r.stdout + r.stderr)[-200:], source[:200]))
check("250 mutated scripts give clean errors only", not bad and timeouts < 25, repr((bad[:2], timeouts)))

# ---------------------------------------------------------------------------
# Random keys


def ctl(c):
    return bytes([ord(c) & 31])


def meta(c):
    return b"\x1b" + c.encode()


COMMANDS = ["forward_word", "kill_line", "yank", "undo", "split_window", "other_window", "delete_window",
            "comment_dwim", "fill_paragraph", "transpose_words", "transpose_lines", "upcase_region",
            "dabbrev_expand", "set_mark", "exchange_point_and_mark", "kill_region", "query_replace",
            "isearch_forward", "goto_line", "toggle_read_only", "display_line_numbers_mode",
            "start_kbd_macro", "end_kbd_macro", "call_last_kbd_macro", "just_one_space",
            "delete_indentation", "zap_to_char", "count_words_region", "ada_mode", "list_buffers",
            "describe_bindings", "about_avoe", "revert_buffer", "indent_line", "forward_sexp"]
PLAIN = [bytes([c]) for c in b"abcxyz (){};:=\"'\t\r\x7f-_0123456789"] + ["é".encode(), "漢".encode()]
SPECIAL = ([ctl(c) for c in "abdefgklnoprstvwy_ "] + [meta(c) for c in "bcdfgluvwy<>%;/qmz{}^t= "]
           + [ctl("x") + k for k in [b"2", b"3", b"1", b"0", b"o", b"b", ctl("x"), ctl("t"), ctl("u"),
                                      b"h", b"u", b"k", ctl("q"), b"(", b")", b"e"]]
           + [b"\x1b[A", b"\x1b[B", b"\x1b[C", b"\x1b[D", b"\x1b[5~", b"\x1b[6~", b"\x1b[1;5C", b"\x1b"])


def fuzz_keys(seed, count):
    rnd = random.Random(seed)
    work = os.path.join(sandbox, "keys-%d" % seed)
    os.makedirs(work)
    names = []
    for name, text in (("a.adb", "procedure A is\nbegin\n   null;\nend A;\n"), ("b.c", "int main() {\n  return 0;\n}\n"),
                       ("d.txt", "hello world\n" * 30)):
        with open(os.path.join(work, name), "w") as f:
            f.write(text)
        names.append(name)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(work)
        os.execve(AVOE, [AVOE, "-q"] + names, ENV)
    rows, cols = rnd.choice([(24, 80), (8, 20), (50, 200), (4, 12)])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    out = bytearray()

    def pump(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.01)
            if r:
                try:
                    out.extend(os.read(fd, 65536))
                except OSError:
                    return
            if len(out) > 2_000_000:
                del out[:1_000_000]

    pump(0.3)
    exited = None
    for _ in range(count):
        r = rnd.random()
        if r < 0.45:
            k = rnd.choice(PLAIN)
        elif r < 0.85:
            k = rnd.choice(SPECIAL)
        elif r < 0.95:
            k = meta("x") + rnd.choice(COMMANDS).encode() + b"\r"
        else:
            k = ctl("u") + str(rnd.choice([0, 1, 4, 50, 1000])).encode()
        if rnd.random() < 0.02:
            rows, cols = rnd.choice([(24, 80), (5, 15), (2, 5), (60, 250)])
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
            os.kill(pid, signal.SIGWINCH)
        try:
            os.write(fd, k)
        except OSError:
            break
        pump(0.004)
        p, status = os.waitpid(pid, os.WNOHANG)
        if p:
            exited = os.waitstatus_to_exitcode(status)
            break
    responsive = False
    if exited is None:
        # Leave any prompt on a normal screen and ask where the cursor is
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        os.kill(pid, signal.SIGWINCH)
        pump(0.2)
        mark = len(out)
        for k in [ctl("g"), ctl("g"), ctl("g"), meta("x"), b"what_cursor_position\r"]:
            os.write(fd, k)
            pump(0.2)
        pump(0.5)
        responsive = b"point=" in out[mark:]
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    return exited, responsive


for seed in (20, 71, 75, 300, 301, 302):
    exited, responsive = fuzz_keys(seed, 500)
    errors = open(ERROR_LOG).read()[-500:] if os.path.exists(ERROR_LOG) else ""
    check("500 random keys (seed %d): no internal error, still responsive" % seed,
          exited is None and responsive and not errors, repr((exited, responsive, errors)))

finish()
