# ***************************************************************************
#                            Avoe - test_scripts
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

"""Phase 3: Avoe script language, editor API, init file, M-:."""

import os

from harness import run, batch, ctl, meta, check, path, read, finish, ROOT

EXAMPLE = os.path.join(ROOT, "examples", "avoerc.avoe")


def expect_out(name, script, expected, files=()):
    code, out, err = batch(script, files)
    check(name, code == 0 and out == expected, repr((code, out, err)))


def expect_err(name, script, fragments):
    code, out, err = batch(script)
    check(name, code != 0 and all(f in err for f in fragments), repr((code, out, err)))


expect_out("arithmetic and images", '''
Message (Image (2 + 3 * 4));
Message (Integer'Image (7));
Message ("x" & 'y');
Message (Image (-7 mod 3) & " " & Image (-7 rem 3) & " " & Image (2 ** 10) & " " & Image (abs (-4)));
Message (Image (16#FF# + 1_000));
''', "14\n 7\nxy\n-1 -1 1024 4\n1255\n")

expect_out("in out parameters, defaults, named arguments", '''
procedure Swap (A, B : in out Integer) is
   T : constant Integer := A;
begin
   A := B;
   B := T;
end Swap;

function Greet (Who : String := "World"; Punct : Character := '!') return String is
begin
   return "Hello, " & Who & Punct;
end Greet;

procedure Get_Answer (Result : out Integer) is
begin
   Result := 42;
end Get_Answer;

X := 1; Y := 2;
Swap (X, Y);
Message (Image (X) & "," & Image (Y));
Message (Greet);
Message (Greet (Punct => '?', Who => "Ada"));
Get_Answer (Z);
Message (Image (Z));
''', "2,1\nHello, World!\nHello, Ada?\n42\n")

expect_out("recursion, loops, case, blocks", '''
function Fact (N : Natural) return Positive is
begin
   if N = 0 then
      return 1;
   else
      return N * Fact (N - 1);
   end if;
end Fact;

Message (Image (Fact (20)));
S := "";
for I in reverse 1 .. 3 loop
   S := S & Image (I);
end loop;
Message (S);
N := 0;
loop
   N := N + 1;
   exit when N >= 5;
end loop;
while N < 8 loop
   N := N + 1;
end loop;
Message (Image (N));
case N is
   when 1 | 2  => Message ("small");
   when 3 .. 9 => Message ("medium");
   when others => Message ("big");
end case;
declare
   Inner : constant String := "block";
begin
   Message (Inner);
end;
''', "2432902008176640000\n321\n8\nmedium\nblock\n")

expect_out("strings and attributes", '''
T := "Hello World";
Message (T (1 .. 5));
Message (Image (T'Length));
Message (Image (T (7)));
Message (Image (Index (T, "World")));
Message (Upcase (T));
Message (Image (Integer'Value (" 42 ") + 1));
Message (Image (Character'Pos ('A')));
Message (Image (Character'Val (66)));
Message ((if T'Length > 5 then "long" else "short"));
Message (Image (3 in 1 .. 5) & " " & Image (3 not in 1 .. 5));
Message (Boolean'Image (True) & Integer'Max (3, 9)'Image);
Message ("say ""hi""");
''', "Hello\n11\nW\n7\nHELLO WORLD\n43\n65\nB\nlong\nTrue False\nTRUE 9\nsay \"hi\"\n")

expect_err("range check with position", "X : Natural := 5;\nX := X - 10;\n", [":2:1:", "out of range"])
expect_err("undefined name", "Foo (1);\n", ["undefined name foo"])
expect_err("syntax error", "if X then\n", ["expected"])
expect_err("no implicit conversion", "Y := 1 + \"2\";\n", ["needs Integer operands"])
expect_err("no interactive input in batch mode", "S := Read_String (\"x\");\n", ["batch mode"])
expect_err("constants", "C : constant := 1;\nC := 2;\n", ["constant"])
expect_err("division by zero", "X := 1 / 0;\n", ["division by zero"])
expect_err("function without return", "function F return Integer is\nbegin\n null;\nend F;\nX := F;\n",
           ["without returning"])
expect_err("in parameters are constant", "procedure P (A : Integer) is\nbegin\n A := 1;\nend P;\nP (3);\n",
           ["constant"])
expect_err("end name must match", "procedure P is\nbegin\n null;\nend Q;\n", ["does not match"])
expect_err("exit outside a loop", "exit;\n", ["exit outside a loop"])
expect_err("endless recursion", "procedure R is\nbegin\n R;\nend R;\nR;\n", ["nested too deeply"])

f = path("api.txt", "one\ntwo\nthree\n")
expect_out("editor API and commands", '''
Goto_Char (Point_Max);
Insert ("four" & LF);
Goto_Char (1);
if Search_Forward ("two") then
   Message ("found at line" & Line_Number'Image);
end if;
Beginning_Of_Line;
Kill_Line (2);
Message (Current_Line);
Save_Buffer;
''', "found at line 2\nthree\nWrote " + f + "\n", files=[f])
check("editor API changed the file", read(f) == "one\nthree\nfour\n", repr(read(f)))

expect_out("script commands", '''
procedure Hello is
   pragma Command;
begin
   Insert ("hi");
end Hello;

Run_Command ("hello");
Hello;
Message (Buffer_Text);
Message (Image (Command_Exists ("hello")));
''', "hihi\nTrue\n")

code, out, err = batch(read(EXAMPLE) + '''
Insert ("hello big world");
Message (Image (Count_Words));
Duplicate_Line;
Message (Buffer_Text);
''')
check("example init file works", code == 0 and out == "3\nhello big world\nhello big world\n",
      repr((code, out, err)))

rc = path("scripts/home/.avoerc", read(EXAMPLE))
env = dict(os.environ, HOME=os.path.dirname(rc))

f = path("dup.txt", "abc\n")
code, out = run([f], [ctl("c"), b"d", ctl("x"), ctl("s"), ctl("x"), ctl("c")], env=env)
check("init file command on C-c d", read(f) == "abc\nabc\n" and code == 0, repr((code, read(f))))

code, out = run([], [meta(":"), b"2 ** 10\r", ctl("x"), ctl("c")], env=env)
check("M-: evaluates an expression", b"1024" in out and code == 0, repr(code))

code, out = run(["-q"], [meta(":"), b"loop null; end loop;\r", ctl("g"), ctl("x"), ctl("c")])
check("C-g interrupts an endless loop", b"Quit" in out and code == 0, repr(code))

code, out = run(["-q"], [ctl("c"), b"d", ctl("x"), ctl("c")], env=env)
check("-q skips the init file", b"C-c is undefined" in out and code == 0, repr(code))

bad = path("scripts/bad/.avoerc", "Set_Tab_Width (4)\nX := 1;\n")
code, out = run([], [ctl("x"), ctl("c")], env=dict(os.environ, HOME=os.path.dirname(bad)))
check("init file error is shown", b"Error in init file" in out and b"~/.avoerc:2:1" in out
      and code == 0, repr(out[-300:]))

f = path("evalbuf.avoe", "procedure Shout is\n   pragma Command;\nbegin\n   Message (\"LOUD\");\nend Shout;\n")
code, out = run(["-q", f], [meta("x"), b"eval_buffer\r", meta("x"), b"shout\r", ctl("x"), ctl("c")])
check("eval_buffer defines an M-x command", b"LOUD" in out and code == 0, repr(code))

finish()
