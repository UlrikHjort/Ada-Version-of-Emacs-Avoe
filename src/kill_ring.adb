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

with Ada.Containers.Vectors;

package body Kill_Ring is

   package Text_Vectors is new Ada.Containers.Vectors (Positive, Unbounded_String);

   Ring       : Text_Vectors.Vector;
   Yank_Index : Positive := 1;

   procedure Push (Text : Unbounded_String) is
   begin
      Ring.Prepend (Text);
      if Natural (Ring.Length) > Max_Entries then
         Ring.Delete_Last;
      end if;
      Yank_Index := 1;
   end Push;

   --  Consecutive kills make one entry.  Backward kills (M-DEL) add in
   --  front, so the entry keeps the text in buffer order.
   procedure Append_To_Newest (Text : Unbounded_String; Before : Boolean) is
   begin
      if Ring.Is_Empty then
         Push (Text);
      elsif Before then
         Ring.Replace_Element (1, Text & Ring (1));
      else
         Ring.Replace_Element (1, Ring (1) & Text);
      end if;
      Yank_Index := 1;
   end Append_To_Newest;

   function Is_Empty return Boolean is (Ring.Is_Empty);

   function Current return Unbounded_String is
     (if Ring.Is_Empty then Null_Unbounded_String else Ring (Yank_Index));

   --  M-y: the next older entry, wrapping around to the newest
   procedure Rotate is
   begin
      if not Ring.Is_Empty then
         Yank_Index := Yank_Index mod Natural (Ring.Length) + 1;
      end if;
   end Rotate;

end Kill_Ring;
