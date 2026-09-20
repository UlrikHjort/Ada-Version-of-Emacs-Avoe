# ***************************************************************************
#                           Avoe - test_robustness
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

"""Hostile scripts, edge-case arguments and big repeat counts must give
clean errors, never internal errors, crashes or hangs."""

import os
import time

from harness import run, batch, ctl, meta, check, path, read, finish


def clean(code, out, err):
    text = out + err
    return code in (0, 1) and not any(s in text for s in
                                      ("fatal", "Internal error", ".adb:", "check failed",
                                       "_ERROR", "stack overflow"))


code, out, err = batch("X := " + "(" * 100000 + "1" + ")" * 100000 + ";\n")
check("very deep nesting is an error, not a crash", code == 1 and clean(code, out, err), repr(err[-200:]))

code, out, err = batch("X := " + "1 + " * 100000 + "1;\n")
check("a very long operator chain is an error", code == 1 and "nested too deeply" in err, repr(err[-200:]))

code, out, err = batch("if True then\n" * 5000 + "null;\n" + "end if;\n" * 5000)
check("very deeply nested blocks are an error", code == 1 and "nested too deeply" in err, repr(err[-200:]))

code, out, err = batch("X := " + "(" * 300 + "1 + 1" + ")" * 300 + ";\n"
                       + "if True then\n" * 200 + "Message (Image (X));\n" + "end if;\n" * 200
                       + "Y := " + " + ".join(["1"] * 500) + ";\nMessage (Image (Y));\n")
check("reasonable nesting still works", code == 0 and out == "2\n500\n", repr((out, err[-200:])))

code, out, err = batch("function F (N : Integer) return Integer is\nbegin\n   return F (N + 1);\nend F;\n"
                       "X := F (1);\n")
check("endless recursion is reported", code == 1 and "nested too deeply" in err, repr(err))

p = path("robust/garbage.avoe", "")
with open(p, "wb") as f:
    f.write(bytes(range(256)) * 4)
code, out, err = batch(open(p, encoding="latin-1").read())
check("binary garbage is a syntax error", code == 1 and clean(code, out, err), repr(err))

MIN = "(-9223372036854775807 - 1)"
exprs = ["9223372036854775807 + 1", "-" + MIN, "5 / 0", "5 mod 0", "5 rem 0", "2 ** -1", "2 ** 64",
         MIN + " / (-1)", MIN + " mod (-1)", "abs " + MIN, '"abc" (0)', '"abc" (4)',
         '"abc" (0 .. 9)', '"abc" (' + MIN + ' .. 2)', "Character'Val (300)",
         "Integer'Value (\"99999999999999999999\")", "[1,2] (9223372036854775807)",
         "Char_After (9223372036854775807)", "Buffer_Substring (1, 9223372036854775807)",
         "Goto_Char (9223372036854775807)", "Delete_Region (" + MIN + ", 9223372036854775807)",
         "Line_Text (" + MIN + ")", "Index (\"abc\", \"b\", 9223372036854775807)",
         "Re_Search_Forward (\"\\\\(\")", "Match_String (99)", "Indent_To (9223372036854775807)",
         "Set_Tab_Width (0)", "Bind_Key (\"C-x C-x C-x\", \"\")", "Split (\"a,b\", \"\")"]
bad = []
for e in exprs:
    code, out, err = batch('Insert ("hello");\nX := ' + e + ";\nMessage (Image (X));\n")
    if not clean(code, out, err):
        bad.append((e, err[-200:]))
check("edge-case arguments give clean errors", not bad, repr(bad))


def timed(script, files=()):
    start = time.time()
    code, out, err = batch(script, files)
    return code, out, err, time.time() - start


for command in ("open_line", "transpose_chars", "delete_backward_char"):
    code, out, err, secs = timed('Insert ("hello (world)\\n  second line\\n");\n'
                                 'Run_Command ("%s", 100000);\nMessage ("done");\n' % command)
    check("100000 x %s is fast" % command, code == 0 and out.endswith("done\n") and secs < 5,
          repr((code, err, secs)))

code, out, err, secs = timed('Insert ("hello");\nRun_Command ("undo", 1000000);\n'
                             'Message ("[" & Buffer_Text & "]");\n')
check("a huge undo count stops when there is nothing left", code == 0 and out.endswith("\n[]\n") and secs < 5,
      repr((code, out, err, secs)))

# M-; in a read-only buffer used to leave a dangling marker behind, so the
# next deletion crashed
f = path("robust/ro.adb", "procedure A is\nbegin\n   null;\nend A;\n")
keys = [ctl("x"), ctl("q"), ctl("x"), b"h", meta(";"), ctl("x"), ctl("q")]
keys += [meta(">"), b"\r", b"\x7f", b"\x7f", ctl("a"), ctl("k"), b"\r"] * 20
code, out = run(["-q", f], keys + [ctl("x"), ctl("s"), ctl("x"), ctl("c")], delay=0.01)
check("M-; in a read-only buffer, then editing", code == 0 and b"Internal error" not in out
      and b"read-only" in out, repr((code, out[-300:])))

f = path("robust/big.txt", "keep\n")
code, out = run([f], [ctl("u"), b"60000", ctl("o"), ctl("_"), ctl("x"), ctl("s"), ctl("x"), ctl("c")])
check("C-u 60000 C-o is undone in one step", code == 0 and read(f) == "keep\n", repr((code, read(f)[:20])))

finish()
