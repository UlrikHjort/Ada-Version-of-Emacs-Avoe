# ***************************************************************************
#                             Avoe - test_safety
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

"""Safe saving, backups, external changes, auto-save and crash recovery."""

import os
import stat
import subprocess

from harness import run, batch, ctl, meta, check, path, read, finish, WORK

# Permissions and backups
f = path("safe/perm.txt", "a\n")
os.chmod(f, 0o640)
code, out, err = batch('Goto_Char (Point_Max);\nInsert ("b" & LF);\nSave_Buffer;\n', [f])
check("save keeps the file permissions",
      code == 0 and read(f) == "a\nb\n" and stat.S_IMODE(os.stat(f).st_mode) == 0o640,
      repr((code, err, oct(os.stat(f).st_mode))))
check("the first save makes a backup", read(f + "~") == "a\n", repr(read(f + "~")))

code, out, err = batch('Insert ("c");\nSave_Buffer;\nInsert ("d");\nSave_Buffer;\n', [f])
check("one backup per session", read(f + "~") == "a\nb\n" and read(f) == "cda\nb\n",
      repr((read(f + "~"), read(f))))

g = path("safe/nobackup.txt", "x\n")
batch('Set_Backups (False);\nInsert ("y");\nSave_Buffer;\n', [g])
check("Set_Backups (False) makes no backup", read(g) == "yx\n" and not os.path.exists(g + "~"))

# Symbolic links are saved through
real = path("safe/real.txt", "r\n")
link = os.path.join(os.path.dirname(real), "link.txt")
if os.path.lexists(link):
    os.remove(link)
os.symlink(real, link)
batch('Insert ("L");\nSave_Buffer;\n', [link])
check("saving through a symlink keeps the link", os.path.islink(link) and read(real) == "Lr\n",
      repr(read(real)))
check("no temporary files are left behind",
      not [n for n in os.listdir(os.path.dirname(real)) if n.endswith(".avoe-save")])

# Changed by another program
f = path("safe/ext.txt", "orig\n")
p = subprocess.Popen(["sh", "-c", "sleep 0.6; printf 'external\\n' > '%s'" % f])
code, out = run([f], [b"x"] + [b""] * 12 + [ctl("x"), ctl("s"), b"n",
                                            ctl("x"), ctl("c"), b"n", b"y"])
p.wait()
check("saving over an external change asks first",
      b"changed on disk" in out and read(f) == "external\n" and code == 0, repr((code, read(f))))

f = path("safe/revert.txt", "one\n")
p = subprocess.Popen(["sh", "-c", "sleep 0.6; printf 'two\\n' > '%s'" % f])
code, out = run([f], [b""] * 12 + [ctl("e"), b"", ctl("x"), ctl("c")])
p.wait()
check("an unmodified buffer follows external changes", b"Reverted" in out and code == 0,
      repr((code, out[-300:])))

f = path("safe/manual.txt", "x\n")
code, out = run([f], [b"yyy", meta("x"), b"revert_buffer\r", b"y", ctl("x"), ctl("c")])
check("revert_buffer discards changes", read(f) == "x\n" and b"Reverted" in out and code == 0,
      repr((code, out[-300:])))

# Auto-save and recovery
cfg = os.path.dirname(path("safe/cfg/avoe/init.avoe", "Set_Auto_Save (Keys => 5);\n"))
state = os.path.join(WORK, "safe", "state")
env = dict(os.environ, HOME=os.path.join(WORK, "safe"),
           XDG_CONFIG_HOME=os.path.dirname(cfg), XDG_STATE_HOME=state)
f = path("safe/crash.txt", "base\n")
auto = os.path.join(state, "avoe", "auto-save", "#" + f.replace("/", "!") + "#")

code, out = run([f], [b"unsaved!", b"", b""], env=env)   # no exit key: killed like a crash
check("auto-save file written before the crash",
      code is None and os.path.exists(auto) and read(auto).startswith("unsav"), repr(code))

code, out = run([f], [b"y", ctl("x"), ctl("s"), ctl("x"), ctl("c")], env=env)
check("recovery is offered and restores the changes",
      b"recover" in out and read(f).startswith("unsav") and code == 0, repr((code, read(f))))
check("saving removes the auto-save file", not os.path.exists(auto))

code, out = run([f], [b"abcdefg", ctl("x"), ctl("c"), b"n", b"y"], env=env)
check("normal exit removes the auto-save file", code == 0 and not os.path.exists(auto), repr(code))

finish()
