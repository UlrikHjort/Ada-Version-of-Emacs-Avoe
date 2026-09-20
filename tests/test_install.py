# ***************************************************************************
#                            Avoe - test_install
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

"""make install / uninstall, file locations and startup load order."""

import glob
import os
import shutil
import subprocess

import harness
from harness import run, ctl, meta, check, path, finish, ROOT, WORK


def make(*args):
    return subprocess.run(["make", "-s", "-C", ROOT] + list(args),
                          capture_output=True, text=True, timeout=300)


prefix = os.path.join(WORK, "prefix")
r = make("install", "PREFIX=" + prefix)
check("make install succeeds", r.returncode == 0, r.stdout + r.stderr)

installed = os.path.join(prefix, "bin", "avoe")
expected = ["bin/avoe", "share/avoe/00-helpers.avoe", "share/avoe/c-mode.avoe",
            "share/avoe/python-mode.avoe", "share/avoe/shell-mode.avoe",
            "share/doc/avoe/README.md", "share/doc/avoe/LICENSE", "share/doc/avoe/avoe-script.md",
            "share/doc/avoe/avoerc.avoe", "share/man/man1/avoe.1", "etc/avoe/site.avoe"]
missing = [f for f in expected if not os.path.exists(os.path.join(prefix, f))]
check("installed files are in place", not missing, repr(missing))
check("binary is executable", os.access(installed, os.X_OK))

home = path("install/home/.keep", "")
home = os.path.dirname(home)
config = os.path.join(WORK, "install", "config")
env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=config)
env.pop("AVOE_DATA_DIR", None)

r = subprocess.run([installed, "--paths"], capture_output=True, text=True, env=env)
check("--paths shows the installed data directory",
      r.returncode == 0 and prefix + "/share/avoe  (4 scripts)" in r.stdout
      and config + "/avoe/init.avoe" in r.stdout, r.stdout + r.stderr)

c_file = path("install/x.c", "int x;\n")
script = path("install/mode.avoe", "Message (Mode_Name);\n")
r = subprocess.run([installed, "--batch", script, c_file], capture_output=True, text=True, env=env)
check("installed binary finds the bundled modes", r.stdout == "C\n", r.stdout + r.stderr)

# Load order: data, site config, user scripts, init file
with open(os.path.join(prefix, "etc/avoe/site.avoe"), "a") as f:
    f.write('Greeting := "site";\n')
path("install/config/avoe/scripts/10-mine.avoe", 'Greeting := Greeting & "+scripts";\n')
path("install/config/avoe/init.avoe", 'Greeting := Greeting & "+init";\n')

harness.AVOE = installed
code, out = run([], [meta(":"), b"Greeting\r", ctl("x"), ctl("c")], env=env)
check("load order: site, user scripts, init.avoe", b'"site+scripts+init"' in out and code == 0,
      repr(out[-300:]))

code, out = run(["-q"], [meta(":"), b"Greeting\r", ctl("x"), ctl("c")], env=env)
check("-q loads the site config but not user files", b'"site"' in out and b"+scripts" not in out,
      repr(out[-300:]))

os.remove(os.path.join(config, "avoe", "init.avoe"))
path("install/home/.avoerc", 'Greeting := Greeting & "+avoerc";\n')
code, out = run([], [meta(":"), b"Greeting\r", ctl("x"), ctl("c")], env=env)
check("~/.avoerc is used when there is no init.avoe", b'"site+scripts+avoerc"' in out,
      repr(out[-300:]))
harness.AVOE = os.path.join(ROOT, "bin", "avoe")

r = make("install", "PREFIX=" + prefix)
with open(os.path.join(prefix, "etc/avoe/site.avoe")) as f:
    check("reinstall keeps the edited site config", "Greeting" in f.read(), r.stdout)

r = make("uninstall", "PREFIX=" + prefix)
gone = not os.path.exists(installed) and not os.path.exists(os.path.join(prefix, "share/avoe"))
check("make uninstall removes the program and data", r.returncode == 0 and gone, r.stdout + r.stderr)
check("uninstall keeps the site config", os.path.exists(os.path.join(prefix, "etc/avoe/site.avoe")))

stage = os.path.join(WORK, "stage")
r = make("install", "DESTDIR=" + stage, "PREFIX=/usr")
check("DESTDIR staging with PREFIX=/usr uses /etc",
      r.returncode == 0 and os.path.exists(os.path.join(stage, "usr/bin/avoe"))
      and os.path.exists(os.path.join(stage, "etc/avoe/site.avoe"))
      and os.path.exists(os.path.join(stage, "usr/share/avoe/c-mode.avoe")), r.stdout + r.stderr)

# "alr install" copies files with gprinstall, which only knows what avoe.gpr
# lists: the bundled scripts must be installed next to the program too
if shutil.which("gprinstall"):
    gpr_prefix = os.path.join(WORK, "gprinstall")
    r = subprocess.run(["gprinstall", "-p", "-f", "--mode=usage", "--prefix=" + gpr_prefix,
                        "-P", os.path.join(ROOT, "avoe.gpr")],
                       capture_output=True, text=True, cwd=ROOT, timeout=300)
    scripts = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "share/avoe/*.avoe")))
    wanted = (["bin/avoe", "share/doc/avoe/README.md", "share/doc/avoe/LICENSE", "share/man/man1/avoe.1"]
              + ["share/avoe/" + s for s in scripts])
    missing = [p for p in wanted if not os.path.exists(os.path.join(gpr_prefix, p))]
    check("gprinstall installs the program, scripts, docs and man page",
          r.returncode == 0 and not missing, repr((missing, r.stdout[-500:], r.stderr[-500:])))
    check("gprinstall does not install sources or object files",
          not os.path.exists(os.path.join(gpr_prefix, "include"))
          and not os.path.exists(os.path.join(gpr_prefix, "lib")), repr(os.listdir(gpr_prefix)))

    gpr_avoe = os.path.join(gpr_prefix, "bin", "avoe")
    r = subprocess.run([gpr_avoe, "--paths"], capture_output=True, text=True, env=env)
    check("a gprinstall'ed avoe finds its scripts",
          "%s/share/avoe  (%d scripts)" % (gpr_prefix, len(scripts)) in r.stdout, r.stdout + r.stderr)
    r = subprocess.run([gpr_avoe, "--batch", script, c_file], capture_output=True, text=True, env=env)
    check("a gprinstall'ed avoe has the C mode", r.stdout == "C\n", r.stdout + r.stderr)
else:
    print("SKIP gprinstall is not installed")

finish()
