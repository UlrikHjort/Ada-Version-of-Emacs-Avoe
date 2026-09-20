-- ***************************************************************************
--                                Avoe - Paths
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
with Ada.Text_IO;   use Ada.Text_IO;
with Interfaces.C;
with System;

with File_Names;
with Utils;

package body Paths is

   package Env renames Ada.Environment_Variables;

   function C_Exe_Path (Buf : System.Address; Len : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "avoe_exe_path";

   function Get_Env (Name : String) return String is
     (if Env.Exists (Name) then Env.Value (Name) else "");

   --  An XDG base directory: $Variable if it is an absolute path, else
   --  $HOME/Default
   function XDG (Variable, Default : String) return String is
      Value : constant String := Get_Env (Variable);
   begin
      if Value'Length > 0 and then Value (Value'First) = '/' then
         return Value;
      end if;
      return Get_Env ("HOME") & "/" & Default;
   end XDG;

   function Executable return String is
      use type Interfaces.C.int;
      Buf : String (1 .. 4096);
      N   : constant Interfaces.C.int := C_Exe_Path (Buf'Address, Buf'Length);
   begin
      return (if N <= 0 then "" else Buf (1 .. Integer (N)));
   end Executable;

   --  The program is PREFIX/bin/avoe, both when installed and in the build
   --  tree, so the data is found relative to it without configuration
   function Prefix return String is
      Exe : constant String := Executable;
   begin
      if Exe = "" then
         return "";
      end if;
      return Ada.Directories.Containing_Directory (Ada.Directories.Containing_Directory (Exe));
   exception
      when others =>
         return "";
   end Prefix;

   function Data_Directory return String is
   begin
      if Get_Env ("AVOE_DATA_DIR") /= "" then
         return Get_Env ("AVOE_DATA_DIR");
      elsif Prefix = "" then
         return "";
      end if;
      return Prefix & "/share/avoe";
   end Data_Directory;

   --  PREFIX/etc/avoe first, then /etc/avoe, where make install puts the
   --  site config for PREFIX=/usr
   function Site_Config_Candidates return String_Vectors.Vector is
      Result : String_Vectors.Vector;
   begin
      if Prefix /= "" and then Prefix /= "/" then
         Result.Append (Prefix & "/etc/avoe/site.avoe");
      end if;
      if Result.Is_Empty or else Result.First_Element /= "/etc/avoe/site.avoe" then
         Result.Append ("/etc/avoe/site.avoe");
      end if;
      return Result;
   end Site_Config_Candidates;

   function First_Existing (Candidates : String_Vectors.Vector) return String is
   begin
      for C of Candidates loop
         if File_Names.Exists (C) and then not File_Names.Is_Directory (C) then
            return C;
         end if;
      end loop;
      return "";
   end First_Existing;

   function Site_Config_File return String is (First_Existing (Site_Config_Candidates));

   function Config_Directory return String is (XDG ("XDG_CONFIG_HOME", ".config") & "/avoe");

   function User_Scripts_Directory return String is (Config_Directory & "/scripts");

   function Init_File_Candidates return String_Vectors.Vector is
      Result : String_Vectors.Vector;
   begin
      Result.Append (Config_Directory & "/init.avoe");
      if Get_Env ("HOME") /= "" then
         Result.Append (Get_Env ("HOME") & "/.avoerc");
      end if;
      return Result;
   end Init_File_Candidates;

   function Init_File return String is (First_Existing (Init_File_Candidates));

   function State_Directory return String is (XDG ("XDG_STATE_HOME", ".local/state") & "/avoe");

   function Script_Files (Directory : String) return String_Vectors.Vector is
      package Sorting is new String_Vectors.Generic_Sorting;
      use Ada.Directories;
      Result : String_Vectors.Vector;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if Directory = "" or else not File_Names.Is_Directory (Directory) then
         return Result;
      end if;
      Start_Search (Search, Directory, "*.avoe", (Ordinary_File => True, others => False));
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         Result.Append (Full_Name (Item));
      end loop;
      End_Search (Search);
      --  Sorted, so scripts load in a known order (00-helpers.avoe first)
      Sorting.Sort (Result);
      return Result;
   exception
      when others =>
         return Result;
   end Script_Files;

   procedure Print_Report is

      function Status (Path : String) return String is
        (if Path = "" then "(unknown)"
         elsif File_Names.Is_Directory (Path) then
            "(" & Utils.Img (Natural (Script_Files (Path).Length)) & " scripts)"
         elsif File_Names.Exists (Path) then "(found)"
         else "(missing)");

      procedure Line (Label, Path : String; Show_Status : Boolean := True) is
      begin
         Put_Line ("  " & Utils.Pad (Label, 18) & File_Names.Abbreviate (Path)
                   & (if Show_Status then "  " & Status (Path) else ""));
      end Line;

      First : Boolean := True;
   begin
      Put_Line ("avoe looks for files here, loading them in this order:");
      Line ("1. data", Data_Directory);
      for C of Site_Config_Candidates loop
         Line ((if First then "2. site config" else ""), C);
         First := False;
      end loop;
      Line ("3. user scripts", User_Scripts_Directory);
      First := True;
      for C of Init_File_Candidates loop
         Line ((if First then "4. init file" else ""), C);
         First := False;
      end loop;
      Put_Line ("Only the first existing site config and init file is loaded;");
      Put_Line ("-q skips 3 and 4.");
      Line ("executable", Executable, Show_Status => False);
      Line ("state", State_Directory, Show_Status => False);
   end Print_Report;

end Paths;
