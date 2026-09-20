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

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Buffer_List;
with File_IO;
with Paths;

package body Auto_Save is

   Keys_Since_Save : Natural := 0;

   function Directory return String is (Paths.State_Directory & "/auto-save");

   --  As in Emacs: the whole path with / as !, between #s, so files with the
   --  same name in different directories get different auto-save files
   function File_For (File_Name : String) return String is
      Mangled : String := File_Name;
   begin
      for C of Mangled loop
         if C = '/' then
            C := '!';
         end if;
      end loop;
      return Directory & "/#" & Mangled & "#";
   end File_For;

   procedure Save_All is
      Directory_Made : Boolean := False;
   begin
      Keys_Since_Save := 0;
      for I in 1 .. Buffer_List.Count loop
         declare
            B  : constant Buffer_Access := Buffer_List.Get (I);
            Ok : Boolean;
         begin
            --  Only buffers visiting a file, changed since the last auto-save
            if Length (B.File_Name) > 0 and then B.Change_Tick /= B.Auto_Save_Tick then
               if B.Modified then
                  if not Directory_Made then
                     File_IO.Make_Directories (Directory);
                     Directory_Made := True;
                  end if;
                  Write_Copy (B.all, File_For (To_String (B.File_Name)), Ok);
                  if Ok then
                     B.Auto_Save_Tick := B.Change_Tick;
                  end if;
               else
                  --  Changes were undone: nothing left to recover
                  Remove (B.all);
                  B.Auto_Save_Tick := B.Change_Tick;
               end if;
            end if;
         end;
      end loop;
   end Save_All;

   procedure Note_Keystroke is
   begin
      Keys_Since_Save := Keys_Since_Save + 1;
      if Keys_Since_Save >= Interval_Keys then
         Save_All;
      end if;
   end Note_Keystroke;

   procedure Remove (B : Buffer) is
   begin
      if Length (B.File_Name) > 0 then
         File_IO.Delete (File_For (To_String (B.File_Name)));
      end if;
   end Remove;

   procedure Remove_All is
   begin
      for I in 1 .. Buffer_List.Count loop
         Remove (Buffer_List.Get (I).all);
      end loop;
   end Remove_All;

   --  Only an auto-save newer than the file counts: an older one was made
   --  before a later save
   function Recovery_Available (File_Name : String) return Boolean is
      A : constant File_IO.File_Info := File_IO.Info (File_For (File_Name));
      F : constant File_IO.File_Info := File_IO.Info (File_Name);
   begin
      return A.Exists and then (not F.Exists or else A.Mtime > F.Mtime);
   end Recovery_Available;

   --  Replace the buffer's text with the auto-saved text.  The buffer still
   --  visits the file and is modified, so C-x C-s saves what was recovered.
   procedure Recover (B : in out Buffer; Ok : out Boolean) is
      Saved : Buffer;
      Msg   : Unbounded_String;
   begin
      Load (Saved, File_For (To_String (B.File_Name)), Msg, Ok);
      if not Ok then
         return;
      end if;
      Delete (B, 0, Length (B));
      B.Point := 0;
      Insert (B, Text_Of (Saved, 0, Length (Saved)));
      B.Point := 0;
   end Recover;

end Auto_Save;
