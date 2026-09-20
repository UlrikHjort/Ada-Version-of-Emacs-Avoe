# ***************************************************************************
#                         Avoe - test_keyboard_model
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

"""Random editing with the keyboard, in two windows on one buffer, compared
with a model of the same keys.  Undoing everything must give back the
original file."""

import random

from harness import run, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]


class Model:
    """The text, point, the other window's point, the kill ring and the
    previous command's class, changed the way avoe changes them."""

    def __init__(self, text):
        self.t = bytearray(text)
        self.pt = 0
        self.other = 0        # Point of the window that is not selected
        self.ring = []
        self.last = "other"
        self.goal = 0

    def ls(self, p):
        return self.t.rfind(b"\n", 0, p) + 1

    def le(self, p):
        i = self.t.find(b"\n", p)
        return len(self.t) if i < 0 else i

    def insert(self, s):
        p = self.pt
        self.t[p:p] = s
        if self.other > p:
            self.other += len(s)
        self.pt = p + len(s)

    def delete(self, a, b):
        n = b - a
        del self.t[a:b]

        def adjust(m):
            return m - n if m >= b else (a if m > a else m)
        self.pt = adjust(self.pt)
        self.other = adjust(self.other)

    def key(self, name, arg=None):
        n = len(self.t)
        cls = "other"
        if name == "char":
            self.insert(arg)
        elif name == "RET":
            self.insert(b"\n")
        elif name == "DEL":
            if self.pt > 0:
                self.delete(self.pt - 1, self.pt)
        elif name == "C-d":
            if self.pt < n:
                self.delete(self.pt, self.pt + 1)
        elif name == "C-f":
            self.pt = min(n, self.pt + 1)
        elif name == "C-b":
            self.pt = max(0, self.pt - 1)
        elif name == "C-a":
            self.pt = self.ls(self.pt)
        elif name == "C-e":
            self.pt = self.le(self.pt)
        elif name in ("C-n", "C-p"):
            if self.last != "vertical":
                self.goal = self.pt - self.ls(self.pt)
            cls = "vertical"
            if name == "C-n":
                e = self.le(self.pt)
                if e < n:
                    s = e + 1
                    self.pt = min(s + self.goal, self.le(s))
            else:
                s0 = self.ls(self.pt)
                if s0 > 0:
                    s = self.ls(s0 - 1)
                    self.pt = min(s + self.goal, self.le(s))
        elif name == "C-k":
            p = self.pt
            if p < n:
                e = self.le(p)
                q = p
                while q < e and self.t[q] in b" \t":
                    q += 1
                to = e + 1 if (q == e and e < n) else e
                text = bytes(self.t[p:to])
                self.delete(p, to)
                if self.last == "kill" and self.ring:
                    self.ring[0] += text
                else:
                    self.ring.insert(0, text)
                cls = "kill"
        elif name == "C-y":
            if self.ring:
                self.insert(self.ring[0])
                cls = "yank"
        elif name == "M-<":
            self.pt = 0
        elif name == "M->":
            self.pt = n
        elif name == "C-x o":
            self.pt, self.other = self.other, self.pt
        self.last = cls


KEYS = {"RET": b"\r", "DEL": b"\x7f", "C-d": ctl("d"), "C-f": ctl("f"), "C-b": ctl("b"),
        "C-a": ctl("a"), "C-e": ctl("e"), "C-n": ctl("n"), "C-p": ctl("p"), "C-k": ctl("k"),
        "C-y": ctl("y"), "M-<": meta("<"), "M->": meta(">"), "C-x o": ctl("x") + b"o"}
WEIGHTS = [("char", 30), ("RET", 4), ("DEL", 8), ("C-d", 7), ("C-f", 6), ("C-b", 6), ("C-a", 4),
           ("C-e", 4), ("C-n", 7), ("C-p", 7), ("C-k", 9), ("C-y", 5), ("M-<", 1), ("M->", 1),
           ("C-x o", 3)]


def scenario(seed, count):
    rnd = random.Random(seed)
    words = ["ada", "avoe", "emacs", "buffer", "window", "kill", "yank", "x", "", " ", "   "]
    lines = []
    for _ in range(40):
        lines.append(" ".join(rnd.choice(words) for _ in range(rnd.randint(0, 8))))
    text = ("\n".join(lines) + "\n").encode()
    model = Model(text)
    keys = [ctl("x"), b"2"]       # Two windows on the same buffer
    names = [w for w, _ in WEIGHTS]
    weights = [c for _, c in WEIGHTS]
    for _ in range(count):
        name = rnd.choices(names, weights)[0]
        if name == "char":
            c = rnd.choice(b"abcxyz ()-;").to_bytes(1, "big")
            keys.append(c)
            model.key("char", c)
        else:
            keys.append(KEYS[name])
            model.key(name)
    # Send the keys in groups: much faster, and the order is the same
    groups = [b"".join(keys[i:i + 25]) for i in range(0, len(keys), 25)]
    return text, groups, bytes(model.t)


for seed in (11, 12, 13, 14):
    text, keys, expected = scenario(seed, 600)
    f = path("kbmodel/edit-%d.txt" % seed)
    with open(f, "wb") as out:
        out.write(text)
    code, _ = run([f], keys + SAVE_EXIT, delay=0.003)
    got = open(f, "rb").read()
    first = next((i for i, (x, y) in enumerate(zip(got, expected)) if x != y), min(len(got), len(expected)))
    check("600 random editing keys in two windows match the model (seed %d)" % seed,
          code == 0 and got == expected,
          repr((code, len(got), len(expected), first, got[first - 20:first + 20], expected[first - 20:first + 20])))

    f = path("kbmodel/undo-%d.txt" % seed)
    with open(f, "wb") as out:
        out.write(text)
    undo_all = [ctl("u"), b"100000", ctl("_"), meta("<"), b"Z", b"\x7f"]
    code, _ = run([f], keys + undo_all + SAVE_EXIT, delay=0.003)
    check("undoing all of them gives back the original (seed %d)" % seed,
          code == 0 and open(f, "rb").read() == text, repr(code))

finish()
