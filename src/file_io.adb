-- ***************************************************************************
--                               Avoe - File_IO
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
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with System;

package body File_IO is

   function C_Info
     (Path : char_array; Mtime, Size : out Integer_64; Mode : out int) return int
     with Import, Convention => C, External_Name => "avoe_file_info";
   function C_Chmod (Path : char_array; Mode : int) return int
     with Import, Convention => C, External_Name => "avoe_chmod";
   function C_Rename (From, To : char_array) return int
     with Import, Convention => C, External_Name => "avoe_rename";
   function C_Unlink (Path : char_array) return int
     with Import, Convention => C, External_Name => "avoe_unlink";
   function C_Fsync (Path : char_array) return int
     with Import, Convention => C, External_Name => "avoe_fsync_path";
   function C_Realpath (Path : char_array; Buf : System.Address; Len : int) return int
     with Import, Convention => C, External_Name => "avoe_realpath";
   function C_Mkdir (Path : char_array; Mode : int) return int
     with Import, Convention => C, External_Name => "avoe_mkdir";

   function Info (Path : String) return File_Info is
      Mtime, Size : Integer_64;
      Mode        : int;
      R           : constant int := C_Info (To_C (Path), Mtime, Size, Mode);
   begin
      if R = 0 then
         return (others => <>);
      end if;
      return (Exists  => True,
              Regular => R = 1,
              Mtime   => Long_Long_Integer (Mtime),
              Size    => Long_Long_Integer (Size),
              Mode    => Natural (Mode));
   end Info;

   --  Follow symbolic links, so that saving through a link replaces the file
   --  it points to.  A path that cannot be resolved is returned unchanged.
   function Resolve (Path : String) return String is
      Buf : String (1 .. 4096);
      N   : constant int := C_Realpath (To_C (Path), Buf'Address, Buf'Length);
   begin
      return (if N <= 0 then Path else Buf (1 .. Integer (N)));
   end Resolve;

   function Rename (From, To : String) return Boolean is
     (C_Rename (To_C (From), To_C (To)) = 0);

   --  Set_Mode, Sync and Delete ignore failures on purpose: they are
   --  extras around a save that must not make it fail

   procedure Set_Mode (Path : String; Mode : Natural) is
      R : constant int := C_Chmod (To_C (Path), int (Mode));
      pragma Unreferenced (R);
   begin
      null;
   end Set_Mode;

   procedure Sync (Path : String) is
      R : constant int := C_Fsync (To_C (Path));
      pragma Unreferenced (R);
   begin
      null;
   end Sync;

   procedure Delete (Path : String) is
      R : constant int := C_Unlink (To_C (Path));
      pragma Unreferenced (R);
   begin
      null;
   end Delete;

   function Copy (From, To : String) return Boolean is
   begin
      Ada.Directories.Copy_File (From, To, "mode=overwrite");
      Set_Mode (To, Info (From).Mode);
      return True;
   exception
      when others =>
         return False;
   end Copy;

   --  Like mkdir -p: create each parent in turn.  Errors for directories
   --  that already exist do not matter.
   procedure Make_Directories (Path : String; Mode : Natural := 8#700#) is
   begin
      for I in Path'First + 1 .. Path'Last loop
         if Path (I) = '/' then
            declare
               R : constant int := C_Mkdir (To_C (Path (Path'First .. I - 1)), int (Mode));
               pragma Unreferenced (R);
            begin
               null;
            end;
         end if;
      end loop;
      declare
         R : constant int := C_Mkdir (To_C (Path), int (Mode));
         pragma Unreferenced (R);
      begin
         null;
      end;
   end Make_Directories;

end File_IO;
