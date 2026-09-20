# ***************************************************************************
#                             Avoe - test_shell
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

"""Shell commands (M-!, M-|) and grep."""

import os

from harness import run, batch, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]
EXIT = [ctl("x"), ctl("c")]

f = path("sh/a.txt", "text\n")
code, out = run(["-q", f], [meta("!"), b"echo hello from sh\r", b""] + EXIT)
check("M-! shows one line of output as a message", b"hello from sh" in out and code == 0, repr(code))

code, out = run(["-q", f], [ctl("u"), meta("!"), b"printf abc\r", b""] + SAVE_EXIT)
check("C-u M-! inserts the output at point", read(f) == "abctext\n", repr(read(f)))

path("sh/a.txt", "text\n")
code, out = run(["-q", f], [meta("!"), b"printf 'l1\\nl2\\nl3\\n'\r", b""] + EXIT)
check("longer output goes to *Shell Command Output*",
      b"*Shell Command Output*" in out and b"l3" in out and code == 0, repr(code))

code, out = run(["-q", f], [meta("!"), b"exit 3\r", b""] + EXIT)
check("a failing command reports its exit code", b"code 3" in out and code == 0, repr(out[-300:]))

code, out = run(["-q", f], [meta("!"), b"pwd\r", b""] + EXIT)
check("commands run in the directory of the file", os.path.dirname(f).encode() in out,
      repr(out[-300:]))

g = path("sh/sort.txt", "b\na\nc\n")
run(["-q", g], [ctl("x"), b"h", ctl("u"), meta("|"), b"sort\r", b""] + SAVE_EXIT)
check("C-u M-| replaces the region with the output", read(g) == "a\nb\nc\n", repr(read(g)))

path("sh/grep/one.txt", "first line\nthe needle is here\n")
start = path("sh/grep/start.txt", "nothing\n")
target = os.path.join(os.path.dirname(start), "one.txt")
code, out = run(["-q", start], [meta("x"), b"grep\r", b"needle one.txt\r"] + [b""] * 6
                + [ctl("x"), b"`", b"X", ctl("x"), ctl("s"), ctl("x"), ctl("c")])
check("M-x grep results work with next_error",
      read(target) == "first line\nXthe needle is here\n" and code == 0, repr((code, read(target))))

code, out, err = batch('Message ("[" & Trim (Shell_Output ("echo hi")) & "]");\n')
check("script Shell_Output returns the output", code == 0 and out == "[hi]\n", repr((code, out, err)))

finish()
