-- ***************************************************************************
--                              Avoe - Kill_Ring
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

--  The kill ring: recently killed text, newest first.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Kill_Ring is

   Max_Entries : constant := 60;

   procedure Push (Text : Unbounded_String);
   procedure Append_To_Newest (Text : Unbounded_String; Before : Boolean);
   --  Extend the newest entry (consecutive kills accumulate).

   function Is_Empty return Boolean;
   function Current return Unbounded_String;
   --  The entry a yank inserts.

   procedure Rotate;
   --  Move the yank pointer to the next older entry (wrapping).

end Kill_Ring;
