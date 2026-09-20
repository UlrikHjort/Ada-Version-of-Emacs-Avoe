# ***************************************************************************
#                             Avoe - test_modes
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

"""Phase 4: modes, syntax highlighting, Ada indentation, compiling."""

import os
import shutil

from harness import run, batch, ctl, meta, check, path, read, finish

EXPECTED = """procedure Hello is
   X : Integer := 0;
begin
   if X = 0 then
      Put_Line ("zero");
   elsif X > 0 then
      null;
   else
      X := X +
        1;
   end if;
   case X is
      when 0 =>
         null;
      when others =>
         Foo (A,
              B);
   end case;
   for I in 1 .. 3 loop
      null;
   end loop;
end Hello;
"""

files = [path("modes/a.adb", "x\n"), path("modes/s.avoe", "x\n"), path("modes/t.txt", "x\n")]
code, out, err = batch('''
Message (Mode_Name);
Select_Buffer ("s.avoe");
Message (Mode_Name);
Select_Buffer ("t.txt");
Message (Mode_Name);
Set_Mode ("ada");
Message (Mode_Name);
''', files)
check("mode from file name", code == 0 and out == "Ada\nAvoe-Script\nFundamental\nAda\n",
      repr((code, out, err)))

calls = "".join('L ("%s");\n' % line.strip().replace('"', '""') for line in EXPECTED.splitlines())
code, out, err = batch('''
procedure L (Text : String) is
begin
   Insert (Text);
   Reindent_Then_Newline_And_Indent;
end L;

Set_Mode ("ada");
''' + calls + "Message (Buffer_Text);\n")
check("indent while typing", code == 0 and out == EXPECTED + "\n", repr((code, err)) + "\n" + out)

f = path("modes/messy.adb", "".join(l.strip() + "\n" for l in EXPECTED.splitlines()))
code, out, err = batch('''
for I in 1 .. %d loop
   Goto_Line (I);
   Indent_Line;
end loop;
Save_Buffer;
''' % len(EXPECTED.splitlines()), [f])
check("reindent a whole file", code == 0 and read(f) == EXPECTED, repr((code, err)) + "\n" + read(f))

code, out, err = batch('''
Set_Face ("keyword", "1;34");
Bind_Mode_Key ("ada", "C-c i", "indent_line");
Set_Indent_Width (4);
Set_Mode ("ada");
Insert ("if X then" & LF & "Y;");
Indent_Line;
Message (Current_Line);
''')
check("faces, mode keys and indent width from scripts", code == 0 and out == "    Y;\n",
      repr((code, out, err)))

code, out, err = batch('Set_Face ("nonsense", "31");\n')
check("unknown face is an error", code != 0 and "unknown face" in err, repr((code, err)))

home = path("modes/home/.avoerc", '''
procedure Ada_Mode_Hook is
   pragma Command;
begin
   Message ("ada hook ran");
end Ada_Mode_Hook;
''')
env = dict(os.environ, HOME=os.path.dirname(home))

bad = path("modes/comp/bad.adb", "procedure Bad is\nbegin\n   null\nend Bad;\n")
code, out = run([bad], [ctl("x"), ctl("c")], env=env)
check("keywords highlighted", b"\x1b[1;35mprocedure" in out and b"[Ada]" in out, repr(code))
check("mode hook ran", b"ada hook ran" in out)

cmd = b"printf 'bad.adb:3:8: missing \";\"\\n'"
code, out = run(["-q", bad], [meta("x"), b"compile\r", ctl("u"), cmd, b"\r", b"", b"", b"", b"",
                              ctl("x"), b"`", b";", ctl("x"), ctl("s"), ctl("x"), ctl("c")])
data = read(bad)
check("compile, then next_error jumps to the location",
      data.split("\n")[2] == "   null;" and code == 0, repr((code, data)))
check("compilation status shown", b"Compilation finished" in out)

path("modes/comp/bad.adb", "procedure Bad is\nbegin\n   null\nend Bad;\n")
if shutil.which("gnatmake"):
    code, out = run(["-q", bad], [meta("x"), b"compile\r", ctl("u"), b"gnatmake -gnatc -u bad.adb\r"]
                    + [b""] * 20 + [ctl("x"), b"`", b";", ctl("x"), ctl("s"), ctl("x"), ctl("c")])
    check("real GNAT error: next_error jumps to it",
          read(bad).split("\n")[2] == "   null;" and b"bad.adb:3:08" in out and code == 0,
          repr((code, read(bad), out[-400:])))

code, out = run(["-q"], [meta("x"), b"next_error\r", ctl("x"), ctl("c")])
check("next_error without a compilation", b"No compilation buffer" in out and code == 0, repr(code))

finish()
