-- ***************************************************************************
--                               Avoe - Windows
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

--  Windows: horizontal slices of the screen, each showing a buffer.
--
--  The selected window's point is its buffer's Point.  Other windows keep
--  their own point in the Point marker.

with Buffers; use Buffers;

package Windows is

   type Window is record
      Buf      : Buffer_Access;
      Point    : aliased Natural := 0;
      Top      : aliased Natural := 0;  --  Position of the first shown line
      Left_Col : Natural := 0;          --  Horizontal scroll
      Height   : Positive := 1;         --  Text rows, excluding the mode line
   end record;

   type Window_Access is access Window;

   procedure Initialize (B : Buffer_Access; Total_Rows : Positive);
   --  One window showing B, using Total_Rows rows including its mode line.

   function Count return Natural;
   function Get (Index : Positive) return Window_Access;
   function Current return Window_Access;
   function Current_Index return Positive;
   function Current_Buffer return Buffer_Access;

   function Point_Of (W : Window_Access) return Natural;

   procedure Select_Window (Index : Positive);
   procedure Other_Window;

   procedure Show_Buffer (W : Window_Access; B : Buffer_Access);

   procedure Split_Current (Ok : out Boolean);
   procedure Delete_Current (Ok : out Boolean);
   procedure Delete_Others;

   procedure Pop_To_Buffer (B : Buffer_Access);
   --  Show B in some other window (splitting if needed) without selecting it.

   procedure Replace_Buffer (Old, By : Buffer_Access);
   --  Every window showing Old shows By instead.

   procedure Layout (Total_Rows : Positive);
   --  Fit the windows into Total_Rows rows (mode lines included).

end Windows;
