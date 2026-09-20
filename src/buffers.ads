-- ***************************************************************************
--                               Avoe - Buffers
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

--  Text buffers: a gap buffer plus point, mark, markers, undo, file
--  association, searching and UTF-8 / line / column helpers.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gap_Buffers;

package Buffers is

   Tab_Width : Positive := 8;

   Fill_Column : Positive := 70;
   --  Line width for M-q.

   Line_Numbers_Default : Boolean := False;
   --  New buffers show line numbers in the left margin (Set_Line_Numbers).

   Make_Backups : Boolean := True;
   --  Keep the original file as "file~" on the first save of each session.

   Max_Undo_Records : Positive := 20_000;
   Max_Undo_Bytes   : Positive := 16_000_000;
   --  Older undo groups are forgotten beyond these limits.

   Read_Only_Error : exception;

   type Marker_Access is access all Natural;
   --  A position that is kept up to date as text is inserted and deleted.

   type Undo_Kind is (Boundary, Inserted, Deleted);

   type Undo_Record is record
      Kind         : Undo_Kind := Boundary;
      Pos          : Natural := 0;
      Len          : Natural := 0;           --  Inserted: number of bytes
      Text         : Unbounded_String;       --  Deleted: the text removed
      Point_Before : Natural := 0;
      Was_Modified : Boolean := True;        --  Modified flag before change
   end record;

   package Undo_Vectors is new Ada.Containers.Vectors (Positive, Undo_Record);
   package Marker_Vectors is new Ada.Containers.Vectors (Positive, Marker_Access);

   subtype Mode_Kind is Positive;
   --  The major mode (an index into Mode_Defs): decides highlighting,
   --  indentation and mode keymap.  Scripts can define more modes.

   Fundamental_Mode : constant := 1;
   Ada_Mode         : constant := 2;
   Script_Mode      : constant := 3;
   Compilation_Mode : constant := 4;

   type Buffer is limited record
      Text         : Gap_Buffers.Gap_Buffer;
      Mode         : Mode_Kind := Fundamental_Mode;
      Point        : Natural := 0;
      Mark         : Natural := 0;
      Mark_Set     : Boolean := False;
      Mark_Active  : Boolean := False;
      --  Set by set_mark, cleared by any change or C-g: commands such as
      --  M-; act on the region only while it is active.
      Name         : Unbounded_String;
      File_Name    : Unbounded_String;
      Modified     : Boolean := False;
      Read_Only    : Boolean := False;
      Line_Numbers : Boolean := False;  --  Show line numbers in the left margin

      Undo_Enabled : Boolean := True;
      Undo_List    : Undo_Vectors.Vector;
      Undo_Next    : Natural := 0;   --  Where a chain of undos continues
      Undo_Bytes   : Natural := 0;   --  Deleted text held by the undo list
      Undo_Trim_At : Natural := 0;   --  Undo_List length for the next trim attempt

      Change_Tick    : Natural := 0;  --  Counts changes to the text
      Auto_Save_Tick : Natural := 0;  --  Change_Tick when last auto-saved or saved
      Backup_Made    : Boolean := False;
      Disk_Mtime     : Long_Long_Integer := -1;  --  File state when read or
      Disk_Size      : Long_Long_Integer := -1;  --  written (-1: no file)
      Warned_Mtime   : Long_Long_Integer := -1;  --  External change already reported

      Markers      : Marker_Vectors.Vector;

      --  Cached line number of a position, to keep the mode line cheap
      Line_Cache_Pos  : Natural := 0;
      Line_Cache_Line : Positive := 1;
   end record;

   type Buffer_Access is access Buffer;

   function Length (B : Buffer) return Natural;
   function Char_At (B : Buffer; Pos : Natural) return Character;
   function Slice (B : Buffer; From, To : Natural) return String;
   function Text_Of (B : Buffer; From, To : Natural) return Unbounded_String;

   procedure Insert (B : in out Buffer; Text : String);
   procedure Insert (B : in out Buffer; Text : Unbounded_String);
   --  Insert at point; point moves past the text.

   procedure Delete (B : in out Buffer; From, To : Natural);
   --  Delete [From, To), adjusting point, mark and markers.

   procedure Erase (B : in out Buffer);
   --  Remove all text and undo history (ignores Read_Only).

   procedure Register_Marker (B : in out Buffer; M : Marker_Access);
   procedure Unregister_Marker (B : in out Buffer; M : Marker_Access);

   --  Undo
   procedure Add_Undo_Boundary (B : in out Buffer);
   procedure Undo_Step (B : in out Buffer; Continue : Boolean; Ok : out Boolean);
   --  Undo one group of changes.  With Continue, keep walking back from
   --  where the previous undo stopped; otherwise start at the newest
   --  change (which makes it possible to undo an undo).

   --  UTF-8 navigation.  Invalid bytes count as one character each.
   function Char_Length (B : Buffer; Pos : Natural) return Positive;
   function Next_Pos (B : Buffer; Pos : Natural) return Natural;
   function Prev_Pos (B : Buffer; Pos : Natural) return Natural;
   function Code_Point_At (B : Buffer; Pos : Natural) return Natural;

   --  Lines and columns
   function Line_Start (B : Buffer; Pos : Natural) return Natural;
   function Line_End (B : Buffer; Pos : Natural) return Natural;
   function Glyph_Width (B : Buffer; Pos, Col : Natural) return Positive;
   --  Screen cells used by the character at Pos when drawn at column Col.
   function Column_Of (B : Buffer; Pos : Natural) return Natural;
   function Pos_At_Column (B : Buffer; Start, Column : Natural) return Natural;
   --  Position on the line beginning at Start closest to Column.
   function Line_Number (B : in out Buffer; Pos : Natural) return Positive;
   function Pos_Of_Line (B : Buffer; Line : Positive) return Natural;

   --  Searching.  Fold means ASCII case-insensitive.  Result is -1 if
   --  there is no match.
   function Search_Forward
     (B : Buffer; Pattern : String; From : Integer; Fold : Boolean) return Integer;
   --  First match starting at or after From.
   function Search_Backward
     (B : Buffer; Pattern : String; From : Integer; Fold : Boolean) return Integer;
   --  Last match starting at or before From.

   --  Files
   procedure Load
     (B         : in out Buffer;
      File_Name : String;
      Message   : out Unbounded_String;
      Success   : out Boolean);
   --  Replace the buffer contents with the file.  A missing file gives an
   --  empty buffer visiting that name.  On failure the buffer is untouched.

   procedure Save
     (B       : in out Buffer;
      Message : out Unbounded_String;
      Success : out Boolean);
   --  Writes a temporary file and renames it over the original (through
   --  symbolic links, keeping permissions), after making a backup if
   --  Make_Backups.

   procedure Revert
     (B       : in out Buffer;
      Message : out Unbounded_String;
      Success : out Boolean);
   --  Reload the file, keeping point where possible.

   procedure Write_Copy (B : Buffer; Path : String; Success : out Boolean);
   --  Write the text to Path (mode 0600) without changing the buffer.

   function Changed_On_Disk (B : Buffer) return Boolean;
   --  The file was modified by another program since it was read or saved.

end Buffers;
