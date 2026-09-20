# ***************************************************************************
#                             Avoe - test_c_mode
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

"""C mode (share/avoe/c-mode.avoe) and script-defined modes."""

from harness import run, batch, ctl, check, path, read, finish

EXPECTED = r"""#include <stdio.h>

int main(int argc, char **argv)
{
    int i;
    if (argc > 1) {
        printf("%s\n",
            argv[1]);
    } else {
        puts("none");
    }
    for (i = 0; i < 3; i++)
        puts("x");
    switch (i) {
    case 1:
        break;
    default:
        return 1;
    }
    /* a comment
     * more
     */
    return 0;
}
"""

files = [path("c/a.c", "x\n"), path("c/b.h", "x\n")]
code, out, err = batch('Message (Mode_Name);\nSelect_Buffer ("b.h");\nMessage (Mode_Name);\n', files)
check("C mode for .c and .h", code == 0 and out == "C\nC\n", repr((code, out, err)))

calls = "".join('L ("%s");\n' % line.strip().replace('"', '""') for line in EXPECTED.splitlines())
code, out, err = batch('''
procedure L (Text : String) is
begin
   Insert (Text);
   C_Newline_And_Indent;
end L;

Set_Mode ("c");
''' + calls + "Message (Buffer_Text);\n")
check("C indentation while typing", code == 0 and out == EXPECTED + "\n", repr((code, err)) + "\n" + out)

f = path("c/messy.c", "".join(l.strip() + "\n" for l in EXPECTED.splitlines()))
code, out, err = batch('''
for I in 1 .. Line_Count loop
   Goto_Line (I);
   C_Indent_Line;
end loop;
Save_Buffer;
''', [f])
check("reindent a whole C file", code == 0 and read(f) == EXPECTED, repr((code, err)) + "\n" + read(f))

f = path("c/brace.c", "")
code, out = run([f], [b"if (x) {", b"\r", b"y;", b"\r", b"}", ctl("x"), ctl("s"), ctl("x"), ctl("c")])
check("RET indents, } re-indents", read(f) == "if (x) {\n    y;\n}", repr(read(f)))

f = path("c/hl.c", "int main(void) { return 0; /* x */ }\n/* start\nmiddle\n*/\n")
code, out = run([f], [ctl("x"), ctl("c")])
check("types, keywords and comments highlighted",
      b"\x1b[1;36mint" in out and b"\x1b[1;35mreturn" in out and b"\x1b[32m/* x */" in out
      and b"[C]" in out, repr(code))
check("multi-line block comment highlighted", b"\x1b[32mmiddle" in out)

sh = path("c/run.sh", "echo hi # greet\n")
code, out, err = batch('''
Define_Mode (Name => "shell", Extensions => ".sh", Keywords => "echo if then fi",
             Line_Comment => "#");
Message (Mode_Name);
''', [sh])
check("script-defined mode applies to an open buffer", code == 0 and out == "shell\n",
      repr((code, out, err)))

code, out, err = batch('Define_Mode (Name => "ada");\n')
check("built-in modes cannot be redefined", code != 0 and "built-in" in err, repr((code, err)))

finish()
