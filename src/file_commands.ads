-- ***************************************************************************
--                            Avoe - File_Commands
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

--  Files, buffers and windows.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Buffers;               use Buffers;

package File_Commands is

   procedure Register_All;

   function Visit_File (Name : String) return Buffer_Access;
   --  The buffer visiting Name, loading it if needed; null on failure
   --  (with a message).

   procedure Switch_To (B : Buffer_Access);
   --  Show B in the selected window.

   procedure Show_Special (Name : String; Content : Unbounded_String);
   --  Fill a read-only buffer such as "*Help*" and show it in another window.

end File_Commands;
