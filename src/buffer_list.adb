-- ***************************************************************************
--                             Avoe - Buffer_List
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Utils;                 use Utils;

package body Buffer_List is

   package Buffer_Vectors is new Ada.Containers.Vectors (Positive, Buffer_Access);

   List : Buffer_Vectors.Vector;

   procedure Free is new Ada.Unchecked_Deallocation (Buffer, Buffer_Access);

   function Find (Name : String) return Buffer_Access is
   begin
      for B of List loop
         if To_String (B.Name) = Name then
            return B;
         end if;
      end loop;
      return null;
   end Find;

   function Find_File (File_Name : String) return Buffer_Access is
   begin
      for B of List loop
         if To_String (B.File_Name) = File_Name then
            return B;
         end if;
      end loop;
      return null;
   end Find_File;

   function Unique_Name (Base : String; Except : Buffer_Access := null) return String is
      function Taken (Name : String) return Boolean is
         B : constant Buffer_Access := Find (Name);
      begin
         return B /= null and then B /= Except;
      end Taken;
      N : Positive := 2;
   begin
      if not Taken (Base) then
         return Base;
      end if;
      while Taken (Base & "<" & Img (N) & ">") loop
         N := N + 1;
      end loop;
      return Base & "<" & Img (N) & ">";
   end Unique_Name;

   function Create (Name : String) return Buffer_Access is
      B : constant Buffer_Access := new Buffer;
   begin
      B.Name := To_Unbounded_String (Unique_Name (Name));
      B.Line_Numbers := Buffers.Line_Numbers_Default;
      List.Append (B);
      return B;
   end Create;

   procedure Remove (B : in out Buffer_Access) is
      I : constant Natural := List.Find_Index (B);
   begin
      if I /= Buffer_Vectors.No_Index then
         List.Delete (I);
      end if;
      Free (B);
   end Remove;

   function Count return Natural is (Natural (List.Length));

   function Get (Index : Positive) return Buffer_Access is (List (Index));

   procedure Touch (B : Buffer_Access) is
      I : constant Natural := List.Find_Index (B);
   begin
      if I /= Buffer_Vectors.No_Index and then I /= 1 then
         List.Delete (I);
         List.Prepend (B);
      end if;
   end Touch;

   function Other_Buffer (Than : Buffer_Access) return Buffer_Access is
   begin
      for B of List loop
         if B /= Than then
            return B;
         end if;
      end loop;
      return null;
   end Other_Buffer;

   function Complete_Name (Input : String) return String_Vectors.Vector is
      Result : String_Vectors.Vector;
   begin
      for B of List loop
         if Starts_With (To_String (B.Name), Input) then
            Result.Append (To_String (B.Name));
         end if;
      end loop;
      return Result;
   end Complete_Name;

end Buffer_List;
