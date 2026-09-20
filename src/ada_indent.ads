-- ***************************************************************************
--                             Avoe - Ada_Indent
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

--  Indentation for Ada (and Avoe script), GNAT style.
--
--  Line based heuristics: the previous code line decides the indentation
--  (an opener such as "is", "then" or "loop" adds a level, an unclosed
--  parenthesis aligns after it, an unfinished statement is a
--  continuation), and a closer at the start of the line ("end", "else",
--  "when", ...) removes a level.

with Buffers; use Buffers;

package Ada_Indent is

   Indent_Width      : Positive := 3;
   Continuation_Width : Positive := 2;

   function Indentation_For (B : Buffer; Start : Natural) return Natural;
   --  The column the line beginning at Start should be indented to.

   procedure Indent_Line_To (B : in out Buffer; Target : Natural);
   --  Indent the line containing point to column Target (with blanks).

   procedure Indent_Line (B : in out Buffer);
   --  Re-indent the line containing point.  Point stays on the same text,
   --  or moves to the first non-blank if it was in the indentation.

end Ada_Indent;
