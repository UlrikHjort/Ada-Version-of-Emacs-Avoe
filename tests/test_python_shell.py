# ***************************************************************************
#                          Avoe - test_python_shell
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

"""Python and shell modes (share/avoe/python-mode.avoe, shell-mode.avoe)."""

from harness import run, batch, ctl, check, path, read, finish

PYTHON = """def f(x):
    if x > 0:
        return x
    else:
        y = [1,
             2]
        return -x

class A:
    pass
"""
PY_DEDENT = {"class A:"}   # lines the user would dedent by hand

SHELL = """#!/bin/sh
if [ $# -eq 0 ]; then
    echo "none"
else
    for f in "$@"; do
        echo "$f"
    done
fi
case "$1" in
    start)
        run
        ;;
    *)
        usage
        ;;
esac
"""


def typing_script(mode, newline_command, text, dedent=()):
    calls = ""
    for line in text.splitlines():
        if line.strip() in dedent:
            calls += "Indent_To (0);\n"
        calls += 'L ("%s");\n' % line.strip().replace('"', '""')
    return ('procedure L (Text : String) is\nbegin\n   Insert (Text);\n   %s;\nend L;\n'
            'Set_Mode ("%s");\n%sMessage (Buffer_Text);\n' % (newline_command, mode, calls))


files = [path("ps/a.py", "x\n"), path("ps/b.sh", "x\n"), path("ps/.bashrc", "x\n")]
code, out, err = batch('Message (Mode_Name);\nSelect_Buffer ("b.sh");\nMessage (Mode_Name);\n'
                       'Select_Buffer (".bashrc");\nMessage (Mode_Name);\n', files)
check("modes for .py, .sh and .bashrc", code == 0 and out == "Python\nShell\nShell\n",
      repr((code, out, err)))

code, out, err = batch(typing_script("python", "Python_Newline_And_Indent", PYTHON, PY_DEDENT))
check("Python indentation while typing", code == 0 and out == PYTHON + "\n",
      repr((code, err)) + "\n" + out)

code, out, err = batch(typing_script("shell", "Shell_Newline_And_Indent", SHELL))
check("shell indentation while typing", code == 0 and out == SHELL + "\n",
      repr((code, err)) + "\n" + out)

f = path("ps/messy.sh", "".join(l.strip() + "\n" for l in SHELL.splitlines()))
code, out, err = batch('for I in 1 .. Line_Count loop\n   Goto_Line (I);\n   Shell_Indent_Line;\n'
                       'end loop;\nSave_Buffer;\n', [f])
check("reindent a whole shell script", code == 0 and read(f) == SHELL, repr((code, err)) + read(f))

f = path("ps/cycle.py", "")
run([f], [b"if x:", b"\r", b"y", b"\r", b"\t", b"\t", b"z", ctl("x"), ctl("s"), ctl("x"), ctl("c")])
check("Python TAB cycles the indentation", read(f) == "if x:\n    y\nz", repr(read(f)))

f = path("ps/else.py", "")
run([f], [b"if x:", b"\r", b"a", b"\r", b"else:", b"\r", b"b", ctl("x"), ctl("s"), ctl("x"), ctl("c")])
check("Python else lines up on RET", read(f) == "if x:\n    a\nelse:\n    b", repr(read(f)))

f = path("ps/hl.py", 'def f():\n    """doc\n    more\n    """\n    return 1  # done\n')
code, out = run([f], [ctl("x"), ctl("c")])
check("Python keywords and docstrings highlighted",
      b"\x1b[1;35mdef" in out and b"\x1b[32m    more" in out and b"\x1b[32m# done" in out
      and b"[Python]" in out, repr(code))

f = path("ps/hl.sh", 'if [ $# -eq 0 ]; then echo "x"; fi  # real comment\n')
code, out = run([f], [ctl("x"), ctl("c")])
check("shell: # comment highlighted, $# is not",
      b"\x1b[32m# real comment" in out and b"\x1b[32m# -eq" not in out
      and b"\x1b[1;35mif" in out and b"[Shell]" in out, repr(code))

finish()
