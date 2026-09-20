-- ***************************************************************************
--                              Avoe - Auto_Save
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

--  Auto-saving and crash recovery.
--
--  Unsaved changes of file buffers are written to
--  $XDG_STATE_HOME/avoe/auto-save/#!path!to!file# every Interval_Keys
--  keystrokes and after Idle_Seconds without input.  The auto-save file is
--  removed when the buffer is saved, reverted or killed, and when avoe exits
--  normally.  After a crash, visiting the file offers to recover it.

with Buffers; use Buffers;

package Auto_Save is

   Interval_Keys : Positive := 300;
   Idle_Seconds  : Positive := 30;

   function File_For (File_Name : String) return String;

   procedure Save_All;
   --  Auto-save every file buffer with changes not yet auto-saved.

   procedure Note_Keystroke;
   --  Count a command; auto-saves after Interval_Keys of them.

   procedure Remove (B : Buffer);
   procedure Remove_All;

   function Recovery_Available (File_Name : String) return Boolean;
   --  An auto-save file exists that is newer than the file.

   procedure Recover (B : in out Buffer; Ok : out Boolean);
   --  Replace the text with the auto-saved text (undoable).

end Auto_Save;
