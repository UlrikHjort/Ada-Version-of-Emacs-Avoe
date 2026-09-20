-- ***************************************************************************
--                             Avoe - Gap_Buffers
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

with Ada.Unchecked_Deallocation;

package body Gap_Buffers is

   --  The text is Data (0 .. Gap_Start - 1) followed by
   --  Data (Gap_End .. Data'Last).  Inserting and deleting at the gap is
   --  cheap, and the gap follows the editing position around.

   Minimum_Growth : constant := 4096;

   procedure Free is new Ada.Unchecked_Deallocation (Storage, Storage_Access);

   function Capacity (B : Gap_Buffer) return Natural is
     (if B.Data = null then 0 else B.Data'Length);

   function Gap_Length (B : Gap_Buffer) return Natural is
     (B.Gap_End - B.Gap_Start);

   function Length (B : Gap_Buffer) return Natural is
     (Capacity (B) - Gap_Length (B));

   function Element (B : Gap_Buffer; Pos : Natural) return Character is
   begin
      if Pos < B.Gap_Start then
         return B.Data (Pos);
      else
         return B.Data (Pos + Gap_Length (B));
      end if;
   end Element;

   function Slice (B : Gap_Buffer; From, To : Natural) return String is
      Result : String (1 .. To - From);
   begin
      for I in Result'Range loop
         Result (I) := Element (B, From + I - 1);
      end loop;
      return Result;
   end Slice;

   --  Make the gap start at Pos by moving the text between the old and the
   --  new place to the other side of the gap
   procedure Move_Gap (B : in out Gap_Buffer; Pos : Natural) is
      N : Natural;
   begin
      if Pos < B.Gap_Start then
         N := B.Gap_Start - Pos;
         B.Data (B.Gap_End - N .. B.Gap_End - 1) :=
           B.Data (Pos .. B.Gap_Start - 1);
         B.Gap_Start := Pos;
         B.Gap_End := B.Gap_End - N;
      elsif Pos > B.Gap_Start then
         N := Pos - B.Gap_Start;
         B.Data (B.Gap_Start .. B.Gap_Start + N - 1) :=
           B.Data (B.Gap_End .. B.Gap_End + N - 1);
         B.Gap_Start := Pos;
         B.Gap_End := B.Gap_End + N;
      end if;
   end Move_Gap;

   procedure Ensure_Gap (B : in out Gap_Buffer; Needed : Natural) is
      Old     : Storage_Access := B.Data;
      Len     : constant Natural := Length (B);
      New_Cap : Natural;
      After   : Natural := 0;
   begin
      if Gap_Length (B) >= Needed then
         return;
      end if;

      --  At least double the size, so a long insertion reallocates rarely.
      --  The text after the gap moves to the end of the new storage.
      New_Cap := Natural'Max (Capacity (B) * 2, Len + Needed + Minimum_Growth);
      B.Data := new Storage (0 .. New_Cap - 1);

      if Old /= null then
         After := Old'Length - B.Gap_End;
         B.Data (0 .. B.Gap_Start - 1) := Old (0 .. B.Gap_Start - 1);
         B.Data (New_Cap - After .. New_Cap - 1) := Old (B.Gap_End .. Old'Last);
         Free (Old);
      end if;
      B.Gap_End := New_Cap - After;
   end Ensure_Gap;

   procedure Insert (B : in out Gap_Buffer; Pos : Natural; Text : String) is
   begin
      if Text'Length = 0 then
         return;
      end if;
      Ensure_Gap (B, Text'Length);
      Move_Gap (B, Pos);
      for I in Text'Range loop
         B.Data (B.Gap_Start + (I - Text'First)) := Text (I);
      end loop;
      B.Gap_Start := B.Gap_Start + Text'Length;
   end Insert;

   procedure Delete (B : in out Gap_Buffer; From, To : Natural) is
   begin
      if From = To then
         return;
      end if;
      Move_Gap (B, From);
      B.Gap_End := B.Gap_End + (To - From);  --  The gap swallows the text
   end Delete;

   procedure Clear (B : in out Gap_Buffer) is
   begin
      B.Gap_Start := 0;
      B.Gap_End := Capacity (B);
   end Clear;

   overriding procedure Finalize (B : in out Gap_Buffer) is
   begin
      Free (B.Data);
      B.Gap_Start := 0;
      B.Gap_End := 0;
   end Finalize;

end Gap_Buffers;
