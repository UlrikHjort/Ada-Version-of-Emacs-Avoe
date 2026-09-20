# ***************************************************************************
#                            Avoe - test_startup
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

"""Version, the startup screen (*About*) and read-only buffers."""

import os
import re
import subprocess
import tempfile

from harness import run, batch, ctl, meta, check, path, read, finish, AVOE

EXIT = [ctl("x"), ctl("c")]
AUTHOR = "Ulrik Hørlyk Hjort".encode()


def plain(out):
    return re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", out)


version = subprocess.run([AVOE, "--version"], capture_output=True, text=True).stdout.strip()
check("avoe --version", version == "avoe 1.0.0", repr(version))

f = path("startup/a.txt", "hello\n")
code, out = run([f], [b"X", ctl("x"), ctl("s")] + EXIT, splash=True)
screen = plain(out)
check("the startup screen shows version and author",
      b"avoe 1.0.0 - Ada Version Of Emacs" in screen and AUTHOR in screen and b"*About*" in screen,
      repr(screen[:400]))
check("the cursor starts in the file's window", code == 0 and read(f) == "Xhello\n", repr(read(f)))

code, out = run([], [ctl("x"), b"o", b"z"] + EXIT, splash=True)
check("the *About* buffer is read-only", b"Buffer is read-only: *About*" in plain(out), repr(plain(out)[-300:]))

code, out = run([], EXIT)
check("--no-splash hides it", code == 0 and b"*About*" not in plain(out))

home = tempfile.mkdtemp(prefix="avoe-startup-")
with open(os.path.join(home, ".avoerc"), "w") as rc:
    rc.write("Set_Startup_Screen (False);\n")
env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"))
code, out = run([], EXIT, env=env, splash=True)
check("Set_Startup_Screen (False) in ~/.avoerc hides it", code == 0 and b"*About*" not in plain(out),
      repr(plain(out)[:300]))

code, out = run([], EXIT, rows=10, splash=True)
check("no startup screen in a small terminal", code == 0 and b"*About*" not in plain(out))

code, out = run([], [meta("x"), b"about_avoe\r"] + EXIT)
check("M-x about_avoe", b"avoe 1.0.0" in plain(out) and AUTHOR in plain(out))

code, out, err = batch('Message (Image (Read_Only));\nSet_Read_Only (True);\nMessage (Image (Read_Only));\n'
                       'Insert ("x");\n')
check("Set_Read_Only and Read_Only in scripts", out == "False\nTrue\n" and code == 1 and "read-only" in err,
      repr((code, out, err)))

finish()
