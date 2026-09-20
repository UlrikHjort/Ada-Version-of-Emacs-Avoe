-- ***************************************************************************
--                             Avoe - File_Names
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

with Ada.Directories;
with Ada.Environment_Variables;
with Utils;

package body File_Names is

   package Sorting is new String_Vectors.Generic_Sorting;

   function Home return String is
     (if Ada.Environment_Variables.Exists ("HOME")
      then Ada.Environment_Variables.Value ("HOME") else "");

   --  ~ and ~/... become the home directory (~user is not supported)
   function Expand (Name : String) return String is
      H : constant String := Home;
   begin
      if H /= "" and then Name'Length > 0 and then Name (Name'First) = '~'
        and then (Name'Length = 1 or else Name (Name'First + 1) = '/')
      then
         return H & Name (Name'First + 1 .. Name'Last);
      end if;
      return Name;
   end Expand;

   function Abbreviate (Name : String) return String is
      H : constant String := Home;
   begin
      if H = "" or else H = "/" then
         return Name;
      elsif Name = H then
         return "~";
      elsif Utils.Starts_With (Name, H & "/") then
         return "~" & Name (Name'First + H'Length .. Name'Last);
      end if;
      return Name;
   end Abbreviate;

   function Absolute (Name : String) return String is
      E : constant String := Expand (Name);
   begin
      return Ada.Directories.Full_Name (E);
   exception
      when others =>
         return E;
   end Absolute;

   function Is_Directory (Name : String) return Boolean is
      use type Ada.Directories.File_Kind;
   begin
      return Ada.Directories.Exists (Name)
        and then Ada.Directories.Kind (Name) = Ada.Directories.Directory;
   exception
      when others =>
         return False;
   end Is_Directory;

   function Exists (Name : String) return Boolean is
   begin
      return Ada.Directories.Exists (Name);
   exception
      when others =>
         return False;
   end Exists;

   --  With a trailing slash, ready to be the start of a file name prompt
   function Directory_Of (File_Name : String) return String is
      function With_Slash (D : String) return String is
        (if D'Length > 0 and then D (D'Last) = '/' then D else D & "/");
   begin
      if File_Name = "" then
         return With_Slash (Abbreviate (Ada.Directories.Current_Directory));
      else
         return With_Slash
           (Abbreviate (Ada.Directories.Containing_Directory (File_Name)));
      end if;
   exception
      when others =>
         return "";
   end Directory_Of;

   function Simple_Name (File_Name : String) return String is
   begin
      return Ada.Directories.Simple_Name (File_Name);
   exception
      when others =>
         return File_Name;
   end Simple_Name;

   --  The entries of the typed directory that start with the last part of
   --  the input, keeping the input's directory as typed; directories end
   --  in / so that completion can go on into them
   function Complete (Input : String) return String_Vectors.Vector is
      use Ada.Directories;
      Result : String_Vectors.Vector;
      Slash  : Natural := 0;
   begin
      for I in reverse Input'Range loop
         if Input (I) = '/' then
            Slash := I;
            exit;
         end if;
      end loop;

      declare
         Dir_Part : constant String :=
           (if Slash = 0 then "" else Input (Input'First .. Slash));
         Base     : constant String :=
           (if Slash = 0 then Input else Input (Slash + 1 .. Input'Last));
         Dir      : constant String :=
           (if Dir_Part = "" then "." else Expand (Dir_Part));
         Search   : Search_Type;
         Item     : Directory_Entry_Type;
      begin
         if not Is_Directory (Dir) then
            return Result;
         end if;
         Start_Search (Search, Dir, "");
         while More_Entries (Search) loop
            Get_Next_Entry (Search, Item);
            declare
               N : constant String := Simple_Name (Item);
            begin
               if N /= "." and then N /= ".." and then Utils.Starts_With (N, Base) then
                  Result.Append
                    (Dir_Part & N & (if Is_Directory (Full_Name (Item)) then "/" else ""));
               end if;
            exception
               when others =>
                  null;
            end;
         end loop;
         End_Search (Search);
         Sorting.Sort (Result);
         return Result;
      end;
   exception
      when others =>
         return Result;
   end Complete;

end File_Names;
