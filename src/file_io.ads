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

--  File system operations that Ada.Directories does not offer: precise
--  modification times, permissions, atomic rename, fsync, symlinks.

package File_IO is

   type File_Info is record
      Exists  : Boolean := False;
      Regular : Boolean := False;
      Mtime   : Long_Long_Integer := 0;   --  Nanoseconds since the epoch
      Size    : Long_Long_Integer := 0;
      Mode    : Natural := 8#644#;        --  Permission bits
   end record;

   function Info (Path : String) return File_Info;
   --  Follows symbolic links.

   function Resolve (Path : String) return String;
   --  Path with symbolic links resolved, or Path itself if that fails
   --  (for example because the file does not exist yet).

   function Rename (From, To : String) return Boolean;
   procedure Set_Mode (Path : String; Mode : Natural);
   procedure Sync (Path : String);
   procedure Delete (Path : String);
   --  These ignore errors.

   function Copy (From, To : String) return Boolean;
   --  Copy a file, keeping its permissions.

   procedure Make_Directories (Path : String; Mode : Natural := 8#700#);
   --  Like mkdir -p.

end File_IO;
