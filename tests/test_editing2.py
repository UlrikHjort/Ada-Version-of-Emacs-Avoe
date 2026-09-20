# ***************************************************************************
#                            Avoe - test_editing2
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

"""Commenting (M-;), bracket matching and paragraph filling (M-q)."""

from harness import run, batch, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]
C_M_F = b"\x1b\x06"
C_M_B = b"\x1b\x02"

ADA = "procedure P is\n   X : Integer;\nbegin\n   null;\nend P;\n"

f = path("ed2/p.adb", ADA)
run(["-q", f], [ctl("n"), meta(";")] + SAVE_EXIT)
check("M-; comments the current line",
      read(f) == "procedure P is\n   -- X : Integer;\nbegin\n   null;\nend P;\n", repr(read(f)))
run(["-q", f], [ctl("n"), meta(";")] + SAVE_EXIT)
check("M-; on a commented line uncomments it", read(f) == ADA, repr(read(f)))

path("ed2/p.adb", ADA)
run(["-q", f], [b"\x00", ctl("n"), ctl("n"), meta(";")] + SAVE_EXIT)
check("M-; on a region comments its lines",
      read(f) == "-- procedure P is\n--    X : Integer;\nbegin\n   null;\nend P;\n", repr(read(f)))

f = path("ed2/x.py", "x = 1\n")
run(["-q", f], [meta(";")] + SAVE_EXIT)
check("Python comments use #", read(f) == "# x = 1\n", repr(read(f)))

f = path("ed2/x.c", "int x;\n")
run(["-q", f], [meta(";")] + SAVE_EXIT)
check("C comments use //", read(f) == "// int x;\n", repr(read(f)))

f = path("ed2/plain.txt", "text\n")
code, out = run(["-q", f], [meta(";"), ctl("x"), ctl("c")])
check("no comment syntax in Fundamental mode", b"No comment syntax" in out and code == 0, repr(code))

f = path("ed2/b.txt", "(a [b] c)\n")
code, out = run(["-q", f], [ctl("x"), ctl("c")])
check("the bracket at point and its match are highlighted",
      b"\x1b[1;4m(" in out and b"\x1b[1;4m)" in out, repr(out[:400]))

f = path("ed2/s.txt", "(a (b) c) d\n")
run(["-q", f], [C_M_F, b"X"] + SAVE_EXIT)
check("C-M-f jumps over a bracket group", read(f) == "(a (b) c)X d\n", repr(read(f)))

f = path("ed2/t.txt", "x (a (b) c)\n")
run(["-q", f], [ctl("e"), C_M_B, b"Y"] + SAVE_EXIT)
check("C-M-b jumps back over a bracket group", read(f) == "x Y(a (b) c)\n", repr(read(f)))

code, out, err = batch('''
Set_Fill_Column (20);
Insert ("one two three four five six seven eight nine ten");
Fill_Paragraph;
Message (Buffer_Text);
''')
check("M-q fills a paragraph", code == 0 and out == "one two three four\nfive six seven eight\nnine ten\n",
      repr((code, out, err)))

code, out, err = batch('''
Set_Fill_Column (24);
Set_Mode ("ada");
Insert ("   --  alpha beta gamma delta epsilon zeta" & LF & "   --  eta" & LF & "   X := 1;" & LF);
Goto_Char (1);
Fill_Paragraph;
Message (Buffer_Text);
''')
check("M-q fills a comment, keeping its prefix",
      code == 0 and out == "   --  alpha beta gamma\n   --  delta epsilon\n   --  zeta eta\n   X := 1;\n\n",
      repr((code, out, err)))

code, out, err = batch('''
Set_Fill_Column (20);
Insert ("aaa bbb" & LF & "ccc" & LF & LF & "ddd eee" & LF);
Goto_Char (1);
Fill_Paragraph;
Message (Buffer_Text);
''')
check("paragraphs end at blank lines", code == 0 and out == "aaa bbb ccc\n\nddd eee\n\n",
      repr((code, out, err)))

finish()
