-- ***************************************************************************
--                              Avoe - Mode_Defs
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

--  The table of major modes.  The first four are built in; scripts add
--  more with Define_Mode.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Buffers;               use Buffers;
with String_Vectors;

package Mode_Defs is

   type Highlighter_Kind is
     (No_Highlighting, Ada_Highlighting, Compilation_Highlighting, Generic_Highlighting);

   type Mode_Def is record
      Name                : Unbounded_String;  --  "c": for Set_Mode and hooks
      Title               : Unbounded_String;  --  "C": shown in the mode line
      Extensions          : Unbounded_String;
      --  Words separated by blanks.  A word starting with '.' matches a
      --  file name suffix (and the whole name); other words must match
      --  the whole file name.
      Highlighter         : Highlighter_Kind := No_Highlighting;
      Keywords            : Unbounded_String;  --  Stored as " w1 w2 "
      Types               : Unbounded_String;
      Line_Comment        : Unbounded_String;
      Block_Comment_Start : Unbounded_String;
      Block_Comment_End   : Unbounded_String;
      Backslash_Escapes   : Boolean := False;   --  C style "\"" and '\''
      Case_Sensitive      : Boolean := True;
      Formatter           : Unbounded_String;
      --  Shell command that prints the formatted text of the file %f
   end record;

   procedure Set_Formatter (Mode : Mode_Kind; Command : String);

   function Normalize_Name (Name : String) return String;
   --  Lower case, '-' becomes '_'.

   function Define (Def : Mode_Def) return Mode_Kind;
   --  Add a mode, or replace the mode with the same name.

   function Count return Natural;
   function Get (Mode : Mode_Kind) return Mode_Def;
   function Find (Name : String) return Natural;
   --  0 if there is no such mode.

   function For_File (File_Name : String) return Mode_Kind;
   --  Later definitions win, so scripts can override built-in modes.

   function Name (Mode : Mode_Kind) return String;
   function Title (Mode : Mode_Kind) return String;
   function Names return String_Vectors.Vector;

end Mode_Defs;
