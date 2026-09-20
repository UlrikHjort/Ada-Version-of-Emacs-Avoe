# ***************************************************************************
#                            Avoe - test_editing
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

"""Phase 2: undo, prefix argument, kill ring, search, query replace, M-x,
buffers, windows, completion."""

import os
import signal
import time

from harness import run, ctl, meta, check, path, read, finish, AVOE

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]

f = path("u1.txt", "alpha beta\n")
run([f], [ctl("e"), b" gamma", ctl("a"), ctl("k"), ctl("_"), ctl("_")] + SAVE_EXIT)
check("undo a kill, then the typing", read(f) == "alpha beta\n", repr(read(f)))

f = path("u2.txt", "one\n")
run([f], [ctl("e"), b"X", ctl("_"), ctl("f"), ctl("_")] + SAVE_EXIT)
check("undo the undo (redo)", read(f) == "oneX\n", repr(read(f)))

f = path("p1.txt", "")
run([f], [ctl("u"), b"5", b"x", ctl("u"), b"-"] + SAVE_EXIT)
check("C-u 5 x and C-u -", read(f) == "xxxxx----", repr(read(f)))

f = path("k1.txt", "first\nsecond\n")
run([f], [ctl("k"), ctl("k"), ctl("k"), ctl("k"), ctl("y"), meta("y")] + SAVE_EXIT)
check("consecutive kills append", read(f) == "first\nsecond\n", repr(read(f)))

f = path("k2.txt", "aaa bbb ccc")
run([f], [meta("d"), ctl("f"), meta("d"), ctl("e"), ctl("y"), meta("y")] + SAVE_EXIT)
check("M-y cycles the kill ring", read(f) == "  cccaaa", repr(read(f)))

f = path("s1.txt", "foo bar Foo baz foo\n")
run([f], [ctl("s"), b"foo", ctl("s"), b"\r", b"!"] + SAVE_EXIT)
check("isearch repeat ignores case", read(f) == "foo bar Foo! baz foo\n", repr(read(f)))

f = path("s2.txt", "foo bar Foo baz foo\n")
run([f], [meta(">"), ctl("r"), b"ba", ctl("r"), b"\r", b"#"] + SAVE_EXIT)
check("isearch backward", read(f) == "foo #bar Foo baz foo\n", repr(read(f)))

f = path("s3.txt", "abc abd\n")
run([f], [ctl("s"), b"abd", b"\x7f", b"\x7f", ctl("g"), b"Z"] + SAVE_EXIT)
check("isearch C-g returns to the start", read(f) == "Zabc abd\n", repr(read(f)))

f = path("s4.txt", "xx yy\n")
run([f], [ctl("s"), b"yy", ctl("a"), b"<"] + SAVE_EXIT)
check("isearch ends on another key", read(f) == "<xx yy\n", repr(read(f)))

f = path("q1.txt", "cat cat cat cat\n")
code, out = run([f], [meta("%"), b"cat\r", b"dog\r", b"y", b"n", b"!"] + SAVE_EXIT)
check("query replace y n !", read(f) == "dog cat dog dog\n", repr(read(f)))
check("replace count message", b"Replaced 3 occurrences" in out)

f = path("m1.txt", "hello\n")
run([f], [meta("x"), b"upcase-w\t", b"\r"] + SAVE_EXIT)
check("M-x with completion", read(f) == "HELLO\n", repr(read(f)))

fa = path("wa.txt", "AAA\n")
fb = path("wb.txt", "BBB\n")
code, out = run([fa, fb], [ctl("x"), b"2", ctl("x"), b"o", ctl("x"), b"b", b"wb.txt\r",
                           b"b", ctl("x"), b"o", b"a", ctl("x"), ctl("c"), b"y", b"y"], rows=20)
check("two windows, two buffers", read(fa) == "aAAA\n" and read(fb) == "bBBB\n",
      repr((read(fa), read(fb))))

fc = path("wc.txt", "".join("line %d\n" % i for i in range(1, 100)))
run([fc], [ctl("x"), b"2", meta(">"), ctl("x"), b"o", b"TOP", ctl("x"), b"1",
           meta(">"), b"END"] + SAVE_EXIT, rows=12)
data = read(fc)
check("one buffer in two windows", data.startswith("TOPline 1\n") and data.endswith("line 99\nEND"),
      repr(data[:12] + "..." + data[-12:]))

fd = path("completion_target_file.txt", "zzz\n")
code, out = run([], [ctl("x"), ctl("f"), ctl("u"), fd[:-12].encode(), b"\t", b"\r",
                     b"Q", ctl("x"), ctl("s"), ctl("x"), ctl("b"), ctl("x"), b"o", b"y",
                     ctl("x"), b"o", ctl("x"), ctl("c")])
check("find file with TAB completion", read(fd) == "Qzzz\n", repr(read(fd)))
check("buffer list is read-only", b"read-only" in out)

fe = path("ke.txt", "e\n")
code, out = run([fe], [b"E", ctl("x"), b"k", b"\r", b"y", ctl("x"), ctl("c")])
check("kill a modified buffer", code == 0 and read(fe) == "e\n", repr(code))

code, out = run([], [meta("x"), b"describe_key\r", ctl("x"), ctl("f"), ctl("x"), ctl("c")])
check("describe_key", b"C-x C-f runs the command find_file" in out)

# Resizing, including to a tiny window, must not crash
import fcntl, pty, select, struct, termios
pid, fdm = pty.fork()
if pid == 0:
    os.execv(AVOE, [AVOE, "-q", fc])
fcntl.ioctl(fdm, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

def pump(t):
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fdm], [], [], 0.02)
        if r:
            try:
                os.read(fdm, 65536)
            except OSError:
                return

pump(0.3)
os.write(fdm, ctl("x") + b"2")
pump(0.1)
for rows, cols in [(6, 30), (40, 120), (3, 10), (24, 80)]:
    fcntl.ioctl(fdm, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.kill(pid, signal.SIGWINCH)
    pump(0.15)
os.write(fdm, ctl("x") + ctl("c"))
pump(0.3)
p, status = os.waitpid(pid, os.WNOHANG)
check("window resizes", p == pid and os.waitstatus_to_exitcode(status) == 0, repr((p, status)))

finish()
