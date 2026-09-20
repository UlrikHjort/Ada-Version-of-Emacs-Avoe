# ***************************************************************************
#                          Avoe - test_line_numbers
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

"""Line numbers in the left margin (display_line_numbers_mode)."""

import os
import re
import tempfile

from harness import run, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]


def plain(out):
    """Screen output without escape sequences."""
    return re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", out)


text = "".join("line %d\n" % i for i in range(1, 13))

f = path("ln/a.txt", text)
code, out = run(["-q", f], [meta("x"), b"display_line_numbers_mode\r", b"", ctl("x"), ctl("c")])
screen = plain(out)
check("M-x display_line_numbers_mode shows numbers", b" 1 line 1" in screen and b"12 line 12" in screen,
      repr(screen[-600:]))
check("it says so", b"Display-Line-Numbers mode enabled in current buffer" in screen)
check("the cursor's line number is bold", b"\x1b[1m 1\x1b[0m " in out, repr(out[-400:]))
check("the mode line still shows (line,column)", b"(1,0)" in screen)

f = path("ln/b.txt", text)
code, out = run(["-q", f], [meta("x"), b"display_line_numbers_mode\r", meta("x"),
                            b"display_line_numbers_mode\r", ctl("x"), ctl("c")])
check("toggling it off again", b"Display-Line-Numbers mode disabled in current buffer" in plain(out))

f = path("ln/c.txt", text)
code, out = run(["-q", f], [meta("x"), b"display_line_numbers_mode\r", ctl("n"), ctl("n"), ctl("e"),
                            b"X"] + SAVE_EXIT)
check("typing with line numbers shown", read(f).splitlines()[2] == "line 3X", repr(read(f)[:30]))
check("the cursor is placed after the margin", b"\x1b[3;10H" in out, repr(out[-300:]))

long_line = "x" * 200 + "\n"
f = path("ln/d.txt", long_line)
code, out = run(["-q", f], [meta("x"), b"display_line_numbers_mode\r", ctl("e"), b"END"] + SAVE_EXIT)
check("horizontal scrolling with line numbers", read(f) == "x" * 200 + "END\n" and code == 0,
      repr((code, read(f)[-10:])))

home = tempfile.mkdtemp(prefix="avoe-ln-home-")
with open(os.path.join(home, ".avoerc"), "w") as rc:
    rc.write("Set_Line_Numbers (True);\n")
env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"))
f = path("ln/e.txt", text)
code, out = run([f], [ctl("x"), ctl("c")], env=env)
check("Set_Line_Numbers (True) in ~/.avoerc", b" 1 line 1" in plain(out), repr(plain(out)[-400:]))

f = path("ln/g.txt", text)
code, out = run(["-q", f], [meta("x"), b"global_display_line_numbers_mode\r", ctl("x"), b"b", b"\r",
                            ctl("x"), ctl("c")])
check("global_display_line_numbers_mode", b"Global Display-Line-Numbers mode enabled" in plain(out)
      and b" 1 line 1" in plain(out), repr(plain(out)[-400:]))

finish()
