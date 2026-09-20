-- ***************************************************************************
--                                Avoe - Utils
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

--  Small string helpers.  Strings are UTF-8; a "cell" is one code point.

package Utils is

   function Img (N : Integer) return String;
   --  Integer image without the leading blank.

   function Hex (N : Natural) return String;

   function Is_Continuation (C : Character) return Boolean is
     (Character'Pos (C) in 16#80# .. 16#BF#);

   function Cell_Count (S : String) return Natural;

   function Head_Cells (S : String; N : Natural) return String;
   --  The first N code points of S.

   function Tail_Cells (S : String; N : Natural) return String;
   --  The last N code points of S.

   function Pad (S : String; Width : Natural) return String;
   --  S padded with blanks to at least Width cells.

   function Drop_Last_Char (S : String) return String;

   function Decode_First (S : String) return Natural;
   --  Code point of the first UTF-8 character in S (16#FFFD# if invalid).

   function To_Lower (C : Character) return Character;
   function To_Upper (C : Character) return Character;
   --  ASCII only; other bytes are returned unchanged.

   function Starts_With (S, Prefix : String) return Boolean;

end Utils;
