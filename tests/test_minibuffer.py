# ***************************************************************************
#                           Avoe - test_minibuffer
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

"""Editing in the minibuffer and minibuffer history."""

from harness import run, ctl, meta, check, path, read, finish

LEFT, RIGHT, UP, DOWN = b"\x1b[D", b"\x1b[C", b"\x1b[A", b"\x1b[B"
EXIT = [ctl("x"), ctl("c")]


def evaluate(keys):
    """Run M-: with the given keys typed at the prompt, then RET."""
    return [meta(":")] + keys + [b"\r"]


code, out = run(["-q"], evaluate([b"40 + 2junk", ctl("b"), ctl("b"), ctl("b"), ctl("b"), ctl("k")])
                + EXIT)
check("C-b moves inside the input, C-k kills to the end", b"42" in out and code == 0, repr(code))

code, out = run(["-q"], evaluate([b"x41 + 2", ctl("a"), ctl("d")]) + EXIT)
check("C-a and C-d", b"43" in out, repr(out[-200:]))

code, out = run(["-q"], evaluate([b"4 + 0", LEFT, LEFT, LEFT, LEFT, b"4", ctl("e"), b"0"]) + EXIT)
check("arrows and typing in the middle", b"\x1b[24;1H44\x1b[K" in out, repr(out[-200:]))

code, out = run(["-q"], evaluate([b"40 + 5 abc def", meta("\x7f"), meta("\x7f")]) + EXIT)
check("M-DEL deletes words backwards", b"45" in out, repr(out[-200:]))

code, out = run(["-q"], evaluate([b"6 * 7"]) + evaluate([b"50 + 5"])
                + evaluate([meta("p"), meta("p"), b" + 100"]) + EXIT)
check("M-p recalls older input", b"142" in out, repr(out[-300:]))

code, out = run(["-q"], evaluate([b"1 + 1"]) + evaluate([b"2 + 1"])
                + evaluate([UP, UP, DOWN, b" + 1000"]) + EXIT)
check("Up and Down browse the history", b"1003" in out, repr(out[-300:]))

code, out = run(["-q"], evaluate([b"7 + 7"]) + evaluate([meta("n"), b"8 + 8"]) + EXIT)
check("M-n past the newest entry returns to empty input", b"16" in out, repr(out[-300:]))

f = path("mb/target.txt", "hello\n")
code, out = run(["-q"], [ctl("x"), ctl("f"), ctl("u"), f.encode(), b"\r", ctl("x"), b"b", b"*scratch*\r",
                         ctl("x"), ctl("f"), ctl("u"), meta("p"), b"\r", b"X",
                         ctl("x"), ctl("s")] + EXIT)
check("file prompts have their own history", read(f) == "Xhello\n", repr(read(f)))

finish()
