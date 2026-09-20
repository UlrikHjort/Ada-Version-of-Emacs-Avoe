# ***************************************************************************
#                              Avoe - test_exit
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

"""C-x C-c with unsaved buffers, with and without Set_Confirm_Exit."""

import os

from harness import run, ctl, check, path, read, finish

QUESTION = b"Some buffers haven't been saved; leave anyway? (yes or no)"
EXIT = [ctl("x"), ctl("c")]

home = os.path.dirname(path("exit/home/.keep", ""))
config = os.path.join(os.path.dirname(home), "config")
path("exit/config/avoe/init.avoe", "Set_Confirm_Exit (True);\n")
confirm_env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=config)

# Without the setting (the default)
code, out = run(["-q"], [b"hello"] + EXIT)
check("by default a modified *scratch* exits without asking", code == 0 and QUESTION not in out,
      repr(code))

# With Set_Confirm_Exit (True)
code, out = run([], [b"hello"] + EXIT + [b"no\r"], env=confirm_env)
check("no stays", code is None and QUESTION in out, repr(code))

code, out = run([], [b"hello"] + EXIT + [b"no\r"] + EXIT + [b"yes\r"], env=confirm_env)
check("asking again after no, then yes leaves", code == 0, repr(code))

code, out = run([], [b"hello"] + EXIT + [b"y\r"], env=confirm_env)
check("y is not an answer", code is None and b"leave anyway? (please type yes or no)" in out, repr(code))

code, out = run([], [b"hello"] + EXIT + [b"y\r", b"YES\r"], env=confirm_env)
check("YES after a wrong answer leaves", code == 0, repr(code))

code, out = run([], [b"hello"] + EXIT + [ctl("g")], env=confirm_env)
check("C-g cancels exiting", code is None and QUESTION in out, repr(code))

code, out = run([], EXIT, env=confirm_env)
check("nothing unsaved: exit at once", code == 0 and QUESTION not in out, repr(code))

f = path("exit/file.txt", "text\n")
code, out = run([f], [b"X"] + EXIT + [b"n", b"yes\r"], env=confirm_env)
check("declining to save a file, then yes", code == 0 and QUESTION in out and read(f) == "text\n"
      and b"Modified buffers exist" not in out, repr((code, read(f))))

f = path("exit/file2.txt", "text\n")
code, out = run([f], [b"X"] + EXIT + [b"y"], env=confirm_env)
check("saving everything leaves without the question", code == 0 and QUESTION not in out
      and read(f) == "Xtext\n", repr((code, read(f))))

finish()
