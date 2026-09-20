# ***************************************************************************
#                          Avoe - test_script_data
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

"""Avoe script vectors, records and exceptions."""

from harness import run, batch, ctl, meta, check, finish


def expect_out(name, script, expected):
    code, out, err = batch(script)
    check(name, code == 0 and out == expected, repr((code, out, err)))


def expect_err(name, script, fragments):
    code, out, err = batch(script)
    check(name, code != 0 and all(f in err for f in fragments), repr((code, out, err)))


expect_out("vectors", '''
V : Vector := [10, 20, 30];
Message (Image (V'Length) & " " & Image (V (2)) & " " & Image (V'Last));
V (2) := 25;
Append (V, 40);
Prepend (V, 5);
Message (Image (V));
Delete (V, 1);
W := V & [50] & 60;
Message (Image (W) & " " & Image (V = [10, 25, 30, 40]));
Sum := 0;
for X of W loop
   Sum := Sum + X;
end loop;
Message (Image (Sum));
Message (Image (W (2 .. 3)));
E : Vector;
Message (Image (E'Length) & Image (E = []));
''', "3 20 3\n[5, 10, 25, 30, 40]\n[10, 25, 30, 40, 50, 60] True\n215\n[25, 30]\n0True\n")

expect_out("vectors are values", '''
procedure Change (X : in out Vector) is
begin
   X (1) := 7;
end Change;

A := [1, 2];
B := A;
B (1) := 99;
Message (Image (A) & Image (B));
Change (A);
Message (Image (A));
''', "[1, 2][99, 2]\n[7, 2]\n")

expect_out("strings and vectors together", '''
Parts := Split ("a,b,,c", ",");
Message (Image (Parts'Length) & " " & Join (Parts, "+"));
Words := Split ("  hello   big world ");
Message (Join (Words, "|"));
Message (Image (Contains (Words, "big")) & Image (Sort (["pear", "apple", "fig"])));
S : String := "cat";
S (1) := 'b';
Append (S, "s");
Message (S);
for C of "ab" loop
   Message (Image (C));
end loop;
''', '4 a+b++c\nhello|big|world\nTrue["apple", "fig", "pear"]\nbats\na\nb\n')

expect_out("records", '''
P := (X => 1, Y => 2);
P.X := 10;
P.Label := "origin";
Message (Image (P.X + P.Y) & " " & P.Label);
Message (Image (P));
Points := [(X => 1, Y => 1), (X => 2, Y => 4)];
Points (2).Y := 5;
Message (Image (Points (2).Y) & " " & Image (Points'Length));
Q := P;
Q.X := 0;
Message (Image (P.X) & " " & Image (P = Q));
''', '12 origin\n(x => 10, y => 2, label => "origin")\n5 2\n10 False\n')

expect_out("exceptions", '''
Not_Found : exception;

function Find (Items : Vector; Item : String) return Positive is
begin
   for I in 1 .. Items'Length loop
      if Items (I) = Item then
         return I;
      end if;
   end loop;
   raise Not_Found with "no " & Item;
end Find;

procedure Inner is
begin
   raise Program_Error with "inner";
exception
   when Program_Error =>
      Message ("inner handler");
      raise;
end Inner;

begin
   Message (Image (Find (["a", "b"], "b")));
   Message (Image (Find (["a", "b"], "z")));
exception
   when Not_Found =>
      Message ("caught: " & Exception_Message);
end;

begin
   X := 1 / 0;
exception
   when Constraint_Error =>
      Message ("wrong handler");
   when E : others =>
      Message ("runtime: " & Exception_Name & " "
               & Image (Index (Exception_Message (E), "division by zero") > 0));
end;

begin
   Inner;
exception
   when others =>
      Message ("outer: " & Exception_Name & " " & Exception_Message);
end;
''', "2\ncaught: no z\nruntime: script_error True\ninner handler\nouter: program_error inner\n")

expect_err("unhandled exceptions report where they were raised",
           'Oops : exception;\nraise Oops with "bad";\n', [":2:1:", "unhandled exception oops", "bad"])
expect_err("raise; outside a handler", "raise;\n", ["only allowed in an exception handler"])
expect_err("indexing out of range", "V := [1];\nX := V (2);\n", ["index 2 is outside 1 .. 1"])
expect_err("missing record field", "P := (A => 1);\nX := P.B;\n", ["no field b"])

#  The handler's message is built at run time, so its text does not appear in
#  the echoed input
code, out = run(["-q"], [meta(":"), b'begin loop null; end loop; exception when others => '
                         b'Message ("hand" & "led"); end;\r',
                         ctl("g"), ctl("x"), ctl("c")])
check("C-g cannot be caught by a handler", b"Quit" in out and b"handled" not in out and code == 0,
      repr((code, out[-300:])))

finish()
