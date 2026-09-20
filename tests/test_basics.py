# ***************************************************************************
#                             Avoe - test_basics
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

"""Phase 1: typing, movement, killing, UTF-8, files, scrolling."""

from harness import run, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]

f = path("t1.txt")
code, out = run([f], [b"hello world", b"\r", b"second line", ctl("a"), ctl("k"),
                      ctl("y"), ctl("y"), meta("<"), ctl("e"), b" !"] + SAVE_EXIT)
check("typing, kill, yank, save", read(f) == "hello world !\nsecond linesecond line", repr(read(f)))
check("exit code 0", code == 0, repr(code))

f = path("t2.txt", "æøå tab\tx\nline2\n")
code, out = run([f], [b"\x1b[C", b"\x1b[C", ctl("d"), b"\x1b[B", b"\x1b[3~"] + SAVE_EXIT)
check("UTF-8 delete and arrow keys", read(f) == "æø tab\tx\nlie2\n", repr(read(f)))
check("mode line shows the file", b"t2.txt" in out)

f = path("t3.txt", "keep\n")
code, out = run([f], [b"xyz", ctl("x"), ctl("c"), b"n", b"y"])
check("exit without saving", read(f) == "keep\n" and code == 0, repr(code))

f = path("t4.txt")
code, out = run([], [b"abc def ghi", ctl("a"), meta("f"), b"\x00", meta("f"), ctl("w"),
                     ctl("e"), ctl("y"), ctl("x"), ctl("w"), ctl("u"), f.encode(), b"\r",
                     ctl("x"), ctl("c")])
check("region kill and write file", read(f) == "abc ghi def", repr(read(f)))

f = path("t5.txt", "".join("line %d\n" % i for i in range(1, 501)))
code, out = run([f], [meta("g"), b"g", b"250\r", ctl("k"), ctl("v"), ctl("v"), meta("v"),
                      meta(">")] + SAVE_EXIT, rows=10, cols=30)
lines = read(f).split("\n")
check("goto line and kill in a long file", lines[249] == "" and lines[248] == "line 249",
      repr(lines[248:251]))

code, out = run([f], [b"x" * 100, ctl("a"), ctl("e"), ctl("x"), ctl("c"), b"n", b"y"],
                rows=8, cols=20)
check("long line scrolls horizontally", code == 0 and b"$" in out, repr(code))

finish()
