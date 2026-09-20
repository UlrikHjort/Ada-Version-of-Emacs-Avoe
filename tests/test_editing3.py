# ***************************************************************************
#                            Avoe - test_editing3
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

"""Keyboard macros, whitespace/word/line/paragraph commands, M-/ and help
about commands."""

from harness import run, ctl, meta, check, path, read, finish

SAVE_EXIT = [ctl("x"), ctl("s"), ctl("x"), ctl("c")]


def edit(name, text, keys, **kw):
    f = path("e3/" + name, text)
    code, out = run([f], keys + SAVE_EXIT, **kw)
    return read(f), out


# Whitespace and indentation
got, _ = edit("m.txt", "    hello\n", [ctl("e"), meta("m"), b"X"])
check("M-m goes back to the indentation", got == "    Xhello\n", repr(got))

got, _ = edit("bs.txt", "a    b\n", [ctl("f"), ctl("f"), meta("\\")])
check("M-\\ deletes the blanks around point", got == "ab\n", repr(got))

got, _ = edit("spc.txt", "a    b\n", [ctl("f"), ctl("f"), meta(" "), b"|"])
check("M-SPC leaves one space", got == "a |b\n", repr(got))

got, _ = edit("join.txt", "foo   \n    bar\n", [ctl("n"), meta("^"), b"|"])
check("M-^ joins with the previous line", got == "foo| bar\n", repr(got))

got, _ = edit("join2.txt", "f(\n   x)\n", [ctl("n"), meta("^")])
check("M-^ puts no space after an open bracket", got == "f(x)\n", repr(got))

# Zapping, transposing, region case
got, _ = edit("zap.txt", "hello world\n", [meta("z"), b"o", ctl("e"), ctl("y")])
check("M-z kills through a character", got == " worldhello\n", repr(got))

got, _ = edit("zap2.txt", "hello world\n", [ctl("u"), b"2", meta("z"), b"o"])
check("C-u 2 M-z", got == "rld\n", repr(got))

got, out = edit("zap3.txt", "hello\n", [meta("z"), b"q"])
check("M-z reports a missing character", got == "hello\n" and b"Search failed" in out, repr(got))

got, _ = edit("tw.txt", "aaa bbb ccc\n", [meta("f"), meta("t"), b"|"])
check("M-t swaps two words", got == "bbb aaa| ccc\n", repr(got))

got, _ = edit("tw2.txt", "aaa bbb\n", [ctl("f"), meta("t")])
check("M-t inside a word", got == "bbb aaa\n", repr(got))

got, _ = edit("tl.txt", "one\ntwo\nthree\n", [ctl("n"), ctl("x"), ctl("t"), b"|"])
check("C-x C-t swaps two lines", got == "two\none\n|three\n", repr(got))

got, _ = edit("up.txt", "hello world\n", [ctl("@"), meta("f"), ctl("x"), ctl("u"), ctl("e"), b"!"])
check("C-x C-u upcases the region", got == "HELLO world!\n", repr(got))

got, _ = edit("down.txt", "HELLO WORLD\n", [ctl("@"), ctl("e"), ctl("x"), ctl("l")])
check("C-x C-l downcases the region", got == "hello world\n", repr(got))

# Paragraphs and counting
got, _ = edit("para.txt", "p1\np1\n\np2\n", [meta("}"), b"X"])
check("M-} moves to the end of the paragraph", got == "p1\np1\nX\np2\n", repr(got))

got, _ = edit("para2.txt", "p1\np1\n\np2\n", [meta(">"), meta("{"), b"Y"])
check("M-{ moves to the start of the paragraph", got == "p1\np1\nY\np2\n", repr(got))

got, out = edit("count.txt", "one two\nthree\n", [meta("=")])
check("M-= counts the buffer", b"Buffer has 2 lines, 3 words and 14 characters" in out, repr(out[-300:]))

# Dynamic abbreviations
got, _ = edit("dab.txt", "foobar fooqux\nfo", [meta(">"), meta("/")])
check("M-/ expands from the nearest word", got == "foobar fooqux\nfooqux", repr(got))

got, _ = edit("dab2.txt", "foobar fooqux\nfo", [meta(">"), meta("/"), meta("/")])
check("M-/ again tries the next word", got == "foobar fooqux\nfoobar", repr(got))

got, out = edit("dab3.txt", "foobar\nfo", [meta(">"), meta("/"), meta("/")])
check("M-/ goes back to the prefix at the end", got == "foobar\nfo" and b"No further" in out, repr(got))

other = path("e3/dab-other.txt", "zebrafish\n")
f = path("e3/dab4.txt", "ze")
run([f, other], [meta(">"), meta("/")] + SAVE_EXIT)
check("M-/ finds words in other buffers", read(f) == "zebrafish", repr(read(f)))

# Keyboard macros
got, _ = edit("kmacro.txt", "a\nb\nc\n",
              [ctl("x"), b"(", ctl("a"), b"* ", ctl("n"), ctl("x"), b")", ctl("x"), b"e", b"e"])
check("C-x ( C-x ) C-x e e", got == "* a\n* b\n* c\n", repr(got))

got, _ = edit("kmacro2.txt", "1\n2\n3\n4\n",
              [ctl("x"), b"(", ctl("e"), b"!", ctl("n"), ctl("x"), b")", ctl("u"), b"3", ctl("x"), b"e"])
check("C-u 3 C-x e", got == "1!\n2!\n3!\n4!\n", repr(got))

got, _ = edit("kmacro3.txt", "aa bb cc\n",
              [ctl("x"), b"(", meta("x"), b"upcase_word\r", ctl("x"), b")", ctl("x"), b"e", b"e"])
check("a macro with minibuffer input", got == "AA BB CC\n", repr(got))

got, out = edit("kmacro4.txt", "x\n", [ctl("x"), b"e"])
check("C-x e without a macro", got == "x\n" and b"No keyboard macro" in out, repr(got))

got, out = edit("kmacro5.txt", "abc\n",
                [ctl("x"), b"(", ctl("f"), ctl("x"), b"e", ctl("x"), b")", ctl("x"), b"e", b"Z"])
check("a macro does not run itself", got == "abZc\n", repr(got))

# Help about commands
code, out = run(["-q"], [meta("x"), b"describe_function\r", b"find_file\r", ctl("x"), ctl("c")])
check("describe_function", b"find_file is bound to C-x C-f" in out, repr(out[-300:]))

code, out = run(["-q"], [meta("x"), b"apropos_command\r", b"kbd\r", ctl("x"), ctl("c")])
check("apropos_command lists matching commands and keys",
      b"start_kbd_macro" in out and b"C-x (" in out and b"call_last_kbd_macro" in out, repr(out[-400:]))

finish()
