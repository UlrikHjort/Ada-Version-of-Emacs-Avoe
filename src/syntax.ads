-- ***************************************************************************
--                               Avoe - Syntax
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

--  Syntax highlighting.  Highlighting is line based: Ada has no multi-line
--  comments or strings, so each line can be coloured on its own.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Buffers;               use Buffers;

package Syntax is

   type Face is
     (Face_Default, Face_Keyword, Face_Type, Face_Comment, Face_String, Face_Number,
      Face_Error, Face_Warning, Face_Status, Face_Paren);

   type Face_Array is array (Integer range <>) of Face;

   Max_Highlight_Length : constant := 4096;
   --  Longer lines are not highlighted.

   function Has_Highlighting (Mode : Mode_Kind) return Boolean;

   procedure Highlight_Line (B : Buffer; Start, Stop : Natural; Faces : out Face_Array);
   --  Faces for the bytes [Start, Stop); Faces'Range must be Start .. Stop - 1.

   function SGR (F : Face) return String;
   --  Escape sequence that switches the terminal to face F.

   procedure Set_Face (Name : String; Code : String; Ok : out Boolean);
   --  Change a face, e.g. Set_Face ("keyword", "1;34").  Code is an ANSI
   --  SGR parameter list.

   function Mode_Name (Mode : Mode_Kind) return String;

   function Is_Ada_Keyword (Word : String) return Boolean;
   --  Word must be lower case.

   function Parse_Location
     (Text   : String;
      File   : out Unbounded_String;
      Line   : out Natural;
      Column : out Natural) return Boolean;
   --  Recognise "file:line:col: text" and "file:line: text" (GNAT style).

end Syntax;
