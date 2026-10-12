# ***************************************************************************
#                             Avoe - test_chmod
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

"""M-x chmod: ask for a file, then for an octal or symbolic mode."""
import os
import stat

from harness import run, ctl, meta, check, path, finish

EXIT = [ctl("x"), ctl("c")]


def mode_of(p):
    return stat.S_IMODE(os.stat(p).st_mode)


def chmod(name, start_mode, typed, other_file=None):
    """Open a file, run M-x chmod on it (or on other_file) and return the
    resulting mode and what the screen showed."""
    f = path("chmod/" + name, "text\n")
    os.chmod(f, start_mode)
    target = [b"\r"] if other_file is None else [ctl("u"), other_file.encode(), b"\r"]
    code, out = run([f], [meta("x"), b"chmod\r"] + target + [typed + b"\r"] + EXIT)
    return mode_of(f), out, code


m, out, code = chmod("octal.txt", 0o644, b"600")
check("octal mode", m == 0o600 and code == 0, oct(m))
check("the prompt shows the mode it has now", b"now 644 rw-r--r--" in out, repr(out[-400:]))
check("and reports the new one", b"is now 600 rw-------" in out, repr(out[-300:]))

m, _, _ = chmod("exec.txt", 0o644, b"u+x")
check("u+x", m == 0o744, oct(m))

m, _, _ = chmod("nowrite.txt", 0o666, b"a-w")
check("a-w", m == 0o444, oct(m))

m, _, _ = chmod("group.txt", 0o644, b"g=rw,o-rwx")
check("two clauses: g=rw,o-rwx", m == 0o660, oct(m))

m, _, _ = chmod("all.txt", 0o600, b"a=r")
check("a=r", m == 0o444, oct(m))

m, _, _ = chmod("plain.txt", 0o644, b"a+X")
check("a+X leaves a file that is not executable alone", m == 0o644, oct(m))

m, _, _ = chmod("runnable.txt", 0o744, b"a+X")
check("a+X on an executable file sets the other execute bits", m == 0o755, oct(m))

m, _, _ = chmod("setuid.txt", 0o644, b"4755")
check("octal with a special bit", m == 0o4755, oct(m))

m, _, _ = chmod("sticky.txt", 0o644, b"u+s")
check("u+s", m == 0o4644, oct(m))

m, out, _ = chmod("bad.txt", 0o644, b"hello")
check("a mode that makes no sense is refused", m == 0o644 and b"Not a mode: hello" in out,
      repr((oct(m), out[-300:])))

m, out, _ = chmod("empty-clause.txt", 0o644, b"u+x,,g-w")
check("an empty clause is refused", m == 0o644 and b"Not a mode" in out, oct(m))

f = path("chmod/other.txt", "x\n")
os.chmod(f, 0o644)
m, out, _ = chmod("current.txt", 0o644, b"711", other_file=f)
check("chmod on another file than the one being edited",
      mode_of(f) == 0o711 and m == 0o644, (oct(mode_of(f)), oct(m)))

code, out = run([path("chmod/here.txt", "x\n")],
                [meta("x"), b"chmod\r", ctl("u"), b"/does/not/exist\r"] + EXIT)
check("a missing file is reported", b"No such file: /does/not/exist" in out, repr(out[-300:]))

finish()
