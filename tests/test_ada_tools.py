# ***************************************************************************
#                           Avoe - test_ada_tools
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

"""Other-file switching, formatting and the Alire manifest."""

import os
import re
import subprocess

from harness import run, batch, ctl, meta, check, path, read, finish, ROOT, AVOE

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]

# Other file: .adb <-> .ads, .c <-> .h
body = path("tools/pkg-child.adb", "package body Pkg.Child is\nend Pkg.Child;\n")
spec = path("tools/pkg-child.ads", "package Pkg.Child is\nend Pkg.Child;\n")
code, out, err = batch('''
Message (Buffer_Name);
Find_Other_File;
Message (Buffer_Name & " " & Current_Line);
Find_Other_File;
Message (Buffer_Name);
''', [body])
check("find_other_file switches between body and spec",
      code == 0 and out == "pkg-child.adb\npkg-child.ads package Pkg.Child is\npkg-child.adb\n",
      repr((code, out, err)))

lonely = path("tools/lonely.adb", "procedure Lonely is\nbegin\n   null;\nend Lonely;\n")
code, out, err = batch('Find_Other_File;\nMessage (Buffer_Name & " " & Image (Buffer_Size));\n', [lonely])
check("a missing spec opens as a new empty buffer",
      code == 0 and "lonely.ads 0" in out and not os.path.exists(lonely[:-1] + "s"),
      repr((code, out, err)))

c_file = path("tools/m.c", "#include \"m.h\"\n")
path("tools/m.h", "int f(void);\n")
code, out, err = batch('Find_Other_File;\nMessage (Buffer_Name);\n', [c_file])
check("C files switch to their header", code == 0 and out == "m.h\n", repr((code, out, err)))

f = path("tools/k.adb", "procedure K is\nbegin\n   null;\nend K;\n")
code, out = run(["-q", f], [ctl("c"), ctl("o"), ctl("x"), ctl("c")])
check("C-c C-o in Ada mode", b"k.ads" in out and code == 0, repr(code))

# Formatting through a per-mode formatter command
f = path("tools/fmt.adb", "procedure Fmt is\nbegin\n   null;\nend Fmt;\n")
code, out, err = batch('Set_Formatter ("ada", "tr a-z A-Z < %f");\nFormat_Buffer;\nSave_Buffer;\n', [f])
check("format_buffer replaces the text with the formatter's output",
      code == 0 and read(f) == "PROCEDURE FMT IS\nBEGIN\n   NULL;\nEND FMT;\n", repr((code, err, read(f))))

f = path("tools/bad.adb", "procedure Bad is\n")
code, out, err = batch('Set_Formatter ("ada", "echo oops >&2; exit 2");\nFormat_Buffer;\n'
                       'Message (Image (Modified));\n', [f])
check("a failing formatter leaves the buffer unchanged",
      code == 0 and "oops" in out and out.endswith("False\n") and read(f) == "procedure Bad is\n",
      repr((code, out, err)))

f = path("tools/none.txt", "text\n")
code, out, err = batch('Format_Buffer;\n', [f])
check("no formatter for Fundamental mode", code == 0 and "No formatter" in out, repr((code, out, err)))

code, out, err = batch('Set_Formatter ("ada", "no-such-formatter-xyz %f");\nSet_Mode ("ada");\n'
                       'Insert ("x");\nFormat_Buffer;\nMessage (Buffer_Text);\n')
check("a missing formatter program is reported", code == 0 and "not found" in out
      and out.endswith("x\n"), repr((code, out, err)))

# Alire manifest
manifest = os.path.join(ROOT, "alire.toml")
text = read(manifest) if os.path.exists(manifest) else ""
version = subprocess.run([AVOE, "--version"], capture_output=True, text=True).stdout.split()[-1]
m = re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)
check("alire.toml has the MIT license", re.search(r'^licenses\s*=\s*"MIT"', text, re.M) is not None, repr(text[:300]))
check("alire.toml names the crate and its executable",
      re.search(r'^name\s*=\s*"avoe"', text, re.M) and '"avoe"' in text and "avoe.gpr" in text,
      repr(text[:200]))
check("alire.toml version matches avoe --version", m is not None and m.group(1) == version,
      repr((m and m.group(1), version)))

finish()
