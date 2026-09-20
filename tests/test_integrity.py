# ***************************************************************************
#                           Avoe - test_integrity
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

"""Nothing may get lost or changed by mistake: files survive loading and
saving byte for byte, and many random edits on a large file give exactly
the text that a simple model of the same edits gives."""

import os
import random

from harness import run, batch, ctl, meta, check, finish, WORK

CHUNK = 65_536  # Files are read in chunks of this size


def write_bytes(name, data):
    p = os.path.join(WORK, "integrity", name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(data)
    return p


def read_bytes(p):
    with open(p, "rb") as f:
        return f.read()


# Save a buffer even if it was not changed: add a byte and remove it again
FORCE_SAVE = ('Goto_Char (Point_Max);\nInsert ("#");\n'
              'Delete_Region (Point_Max - 1, Point_Max);\nSave_Buffer;\n')

# ---------------------------------------------------------------------------
# Load and save round trips

cases = {
    "empty": b"",
    "all byte values across chunks": bytes(range(256)) * (3 * CHUNK // 256) + b"tail",
    "no final newline": b"line one\nline two",
    "CRLF line ends": b"dos line\r\n" * 20_000,
    "UTF-8 split across a chunk": b"a" * (CHUNK - 1) + "é漢€".encode() * 1000,
    "one very long line": b"x" * (5 * CHUNK + 3),
    "20 MB of lines": b"".join(b"%07d The quick brown fox jumps over the lazy dog.\n" % i
                               for i in range(400_000)),
}
for name, data in cases.items():
    p = write_bytes("roundtrip-%d.txt" % abs(hash(name)), data)
    code, out, err = batch('Message (Image (Buffer_Size));\n' + FORCE_SAVE, [p])
    got = read_bytes(p)
    check("load and save keeps every byte: " + name,
          code == 0 and out.startswith("%d\n" % len(data)) and got == data,
          repr((code, out[:80], err[:200], len(got), len(data))))

# ---------------------------------------------------------------------------
# Random edits compared with a model

PIECES = ["a", "b", "xyz", " ", "\n", "\n\n", "é", "漢", "€", '"', "--", "(", ")",
          "Hello, world", "0123456789"]


def random_text(rnd):
    return "".join(rnd.choice(PIECES) for _ in range(rnd.randint(0, 12)))


def literal(text):
    """An Avoe script expression for text."""
    parts = text.split("\n")
    return " & LF & ".join('"' + p.replace('"', '""') + '"' for p in parts)


def edits(seed, base, count):
    """A script of random edits, and the bytes they must produce."""
    rnd = random.Random(seed)
    model = bytearray(base)
    script = []
    for _ in range(count):
        n = len(model)
        op = rnd.random()
        if op < 0.45:
            # Insert somewhere
            pos = rnd.randint(0, n)
            text = random_text(rnd).encode()
            script.append("Goto_Char (%d);\nInsert (%s);\n" % (pos + 1, literal(text.decode())))
            model[pos:pos] = text
        elif op < 0.8 and n > 0:
            # Delete a region (possibly large)
            a = rnd.randint(0, n)
            b = min(n, a + rnd.choice([0, 1, 2, 17, 300, 5000, 70_000]))
            script.append("Delete_Region (%d, %d);\n" % (a + 1, b + 1))
            del model[a:b]
        elif n > 0:
            # Cut a region and paste it somewhere else
            a = rnd.randint(0, n)
            b = min(n, a + rnd.choice([1, 40, 1000, 100_000]))
            piece = bytes(model[a:b])
            del model[a:b]
            c = rnd.randint(0, len(model))
            script.append("Cut := Buffer_Substring (%d, %d);\nDelete_Region (%d, %d);\n"
                          "Goto_Char (%d);\nInsert (Cut);\n" % (a + 1, b + 1, a + 1, b + 1, c + 1))
            model[c:c] = piece
    return "".join(script), bytes(model)


base = b"".join(b"%06d Some text on this line, with UTF-8: \xc3\xa6\xc3\xb8\xc3\xa5.\n" % i
                for i in range(60_000))  # About 3 MB
for seed in (1, 2, 3):
    p = write_bytes("edits-%d.txt" % seed, base)
    script, expected = edits(seed, base, 1500)
    code, out, err = batch(script + "Save_Buffer;\n", [p])
    got = read_bytes(p)
    check("1500 random edits on a 3 MB file give the expected text (seed %d)" % seed,
          code == 0 and got == expected,
          repr((code, err[:200], len(got), len(expected),
                next((i for i, (x, y) in enumerate(zip(got, expected)) if x != y), None))))

    p = write_bytes("undo-%d.txt" % seed, base)
    code, out, err = batch(script + 'Run_Command ("undo");\n' + FORCE_SAVE, [p])
    got = read_bytes(p)
    check("undoing all of them gives back the original (seed %d)" % seed,
          code == 0 and got == base, repr((code, err[:200], len(got), len(base))))

# ---------------------------------------------------------------------------
# Killing and yanking a whole large file with the keyboard

text = b"".join(b"line %d of a file that is edited with the keyboard\n" % i for i in range(100_000))
SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]

p = write_bytes("kill-yank.txt", text)
code, out = run([p], [ctl("x"), b"h", ctl("w"), ctl("y")] + SAVE_EXIT)
check("C-x h C-w C-y on a 5 MB file changes nothing", code == 0 and read_bytes(p) == text,
      repr((code, len(read_bytes(p)))))

p = write_bytes("copy-yank.txt", text)
code, out = run([p], [ctl("x"), b"h", meta("w"), meta(">"), ctl("y")] + SAVE_EXIT)
check("M-w and C-y at the end doubles a 5 MB file exactly", code == 0 and read_bytes(p) == text * 2,
      repr((code, len(read_bytes(p)))))

p = write_bytes("kill-undo.txt", text)
code, out = run([p], [ctl("x"), b"h", ctl("w"), ctl("_"), meta("<"), b"Z", b"\x7f"] + SAVE_EXIT)
check("killing everything and undoing it gives back every byte", code == 0 and read_bytes(p) == text,
      repr((code, len(read_bytes(p)))))

# ---------------------------------------------------------------------------
# Pasting into the terminal: the text arrives as raw bytes in chunks that can
# split a UTF-8 character; terminals send line breaks as RET

import tempfile

paste_lines = []
for i in range(1500):
    paste_lines.append("%04d\tpasted text: æøå 漢字 € -- (x) := \"y\";   " % i)
paste = "\n".join(paste_lines) + "\n"
raw = paste.replace("\n", "\r").encode()
p = write_bytes("paste.txt", b"")
chunks = [raw[i:i + 509] for i in range(0, len(raw), 509)]   # Odd size: splits characters
code, out = run([p], chunks + SAVE_EXIT, delay=0.01)
check("pasting 80 KB of text arrives exactly", code == 0 and read_bytes(p) == paste.encode(),
      repr((code, len(read_bytes(p)), len(paste.encode()))))

# ---------------------------------------------------------------------------
# Crash recovery of a large UTF-8 file

home = tempfile.mkdtemp(prefix="avoe-recover-")
os.makedirs(os.path.join(home, ".config", "avoe"))
with open(os.path.join(home, ".config", "avoe", "init.avoe"), "w") as rc:
    rc.write("Set_Auto_Save (Keys => 5);\n")
env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"),
           XDG_STATE_HOME=os.path.join(home, "state"))
big = "".join("%06d ünïcödé 漢字 line\n" % i for i in range(40_000)).encode()   # About 1.3 MB
typed = "Ünïcødé 漢字 after a crash!!"
keys = [meta(">")] + [c.encode() for c in typed]
while len(keys) % 5:                  # Auto-save runs every 5 keys
    keys.append(b"x")
    typed += "x"
p = write_bytes("recover.txt", big)
run([p], keys, env=env)               # No exit key: killed like a crash
check("a crash leaves the file on disk unchanged", read_bytes(p) == big)
code, out = run([p], [b"y"] + SAVE_EXIT, env=env)
check("recovering after the crash restores every byte and every change",
      code == 0 and read_bytes(p) == big + typed.encode(), repr((code, len(read_bytes(p)))))

# ---------------------------------------------------------------------------
# replace_string on a large file, compared with Python's replace

data = b"".join(b"aa aaa aaaa ba ab abab %05d \xc3\xa6aa\n" % i for i in range(30_000))
for old, new in ((b"aa", b"b"), (b"ab", b"abab")):
    p = write_bytes("replace-%s.txt" % old.decode(), data)
    code, out = run([p], [meta("x"), b"replace_string\r", old + b"\r", new + b"\r"] + SAVE_EXIT)
    check("replace_string %s with %s over 1 MB matches Python" % (old.decode(), new.decode()),
          code == 0 and read_bytes(p) == data.replace(old, new), repr((code, len(read_bytes(p)))))

p = write_bytes("replace-undo.txt", data)
code, out = run([p], [meta("x"), b"replace_string\r", b"aa\r", b"b\r", ctl("_"), meta("<"), b"Z", b"\x7f"]
                + SAVE_EXIT)
check("one undo takes back a replace of 120,000 matches", code == 0 and read_bytes(p) == data,
      repr((code, len(read_bytes(p)))))

finish()
