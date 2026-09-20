-- ***************************************************************************
--                              Avoe - Brackets
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

--  Matching brackets: ( ) [ ] { }.  Brackets inside strings and comments
--  are not treated specially.

with Buffers; use Buffers;

package Brackets is

   Max_Distance : constant := 200_000;
   --  How far to look for a match.

   function Is_Open (C : Character) return Boolean is (C in '(' | '[' | '{');
   function Is_Close (C : Character) return Boolean is (C in ')' | ']' | '}');

   function Matching (B : Buffer; Pos : Natural) return Integer;
   --  The position of the bracket matching the one at Pos, or -1 if there
   --  is none (or the brackets do not pair up).

   procedure Pair_At (B : Buffer; Point : Natural; Open_Pos, Close_Pos : out Integer);
   --  An opening bracket at Point, or a closing one just before Point, and
   --  its match.  Both are -1 if there is no such matched pair.

end Brackets;
