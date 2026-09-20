# ***************************************************************************
#                             Avoe - test_regex
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

"""Regular expression search and replace."""

from harness import run, batch, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]
C_M_S = b"\x1b\x13"   # ESC C-s
C_M_R = b"\x1b\x12"   # ESC C-r

f = path("re/a.txt", "foo123 bar45 baz\n")
run([f], [C_M_S, b"[0-9]+", b"\r", b"#"] + SAVE_EXIT)
check("C-M-s finds a regexp and leaves point after it", read(f) == "foo123# bar45 baz\n", repr(read(f)))

f = path("re/b.txt", "foo123 bar45 baz\n")
run([f], [C_M_S, b"[0-9]+", ctl("s"), b"\r", b"#"] + SAVE_EXIT)
check("C-s repeats a regexp search", read(f) == "foo123 bar45# baz\n", repr(read(f)))

f = path("re/c.txt", "foo123 bar45 baz\n")
run([f], [meta(">"), C_M_R, b"ba[rz]", b"\r", b"<"] + SAVE_EXIT)
check("C-M-r searches backwards", read(f) == "foo123 bar45 <baz\n", repr(read(f)))

f = path("re/d.txt", "foo BAZ\n")
run([f], [C_M_S, b"baz", b"\r", b"!"] + SAVE_EXIT)
check("a lower-case regexp ignores case", read(f) == "foo BAZ!\n", repr(read(f)))

f = path("re/e.txt", "foo123 bar45 baz\n")
code, out = run([f], [meta("x"), b"replace_regexp\r", b"([a-z]+)([0-9]+)\r", b"\\2\\1\r"] + SAVE_EXIT)
check("replace_regexp with groups", read(f) == "123foo 45bar baz\n" and b"Replaced 2" in out,
      repr(read(f)))

f = path("re/f.txt", "bar bar bar\n")
run([f], [meta("x"), b"query_replace_regexp\r", b"b(a)r\r", b"<\\1\\&>\r", b"y", b"n", b"y"]
    + SAVE_EXIT)
check("query_replace_regexp with \\1 and \\&", read(f) == "<abar> bar <abar>\n", repr(read(f)))

f = path("re/g.txt", "one\ntwo\n")
run([f], [meta("x"), b"replace_regexp\r", b"^\r", b"> \r"] + SAVE_EXIT)
check("^ matches at every line start", read(f) == "> one\n> two\n", repr(read(f)))

f = path("re/h.txt", "abc\n")
code, out = run([f], [C_M_S, b"(", ctl("g"), ctl("g"), ctl("x"), ctl("c")])
check("an invalid regexp is reported, not fatal", b"nvalid" in out and code == 0, repr(code))

f = path("re/i.txt", "x = 10; y = 200;\n")
code, out, err = batch('''
if Re_Search_Forward ("([a-z]) = ([0-9]+)") then
   Message (Match_String (1) & " is " & Match_String (2));
   Message (Image (Match_Beginning) & ".." & Image (Match_End));
end if;
if Re_Search_Forward ("[0-9]+") and then Match_String = "200" then
   Message ("second");
end if;
Goto_Char (Point_Max);
if Re_Search_Backward ("x") then
   Message (Image (Point));
end if;
if not Re_Search_Forward ("zzz") then
   Message ("not found");
end if;
''', [f])
check("script regexp functions", code == 0 and out == "x is 10\n1..7\nsecond\n1\nnot found\n",
      repr((code, out, err)))

finish()
