-- ***************************************************************************
--                               Avoe - Display
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

--  Screen redisplay: all windows with their mode lines, and the echo area.
--  Only rows that changed since the previous frame are rewritten.

with Windows;

package Display is

   procedure Update_Size;
   --  Re-read the terminal size, lay out windows and force a full redraw.

   procedure Invalidate;
   --  Force a full redraw on the next Render.

   function Screen_Rows return Positive;
   function Screen_Cols return Positive;

   procedure Recenter (W : Windows.Window_Access);
   --  Scroll W so that its point is in the middle.

   procedure Set_Highlight (From, To : Natural);
   --  Show [From, To) in the selected window in reverse video.
   procedure Clear_Highlight;

   procedure Render (Echo : String; Echo_Cursor : Integer := -1);
   --  Draw everything.  Echo is the echo area text; if Echo_Cursor >= 0
   --  the cursor is placed in the echo area after that many cells.

end Display;
