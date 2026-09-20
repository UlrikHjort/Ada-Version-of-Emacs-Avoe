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

--  File name helpers: ~ expansion, abbreviation and completion.

with String_Vectors;

package File_Names is

   function Expand (Name : String) return String;
   --  "~/x" -> "$HOME/x"

   function Abbreviate (Name : String) return String;
   --  "$HOME/x" -> "~/x"

   function Absolute (Name : String) return String;
   --  Expanded and made absolute.

   function Is_Directory (Name : String) return Boolean;
   function Exists (Name : String) return Boolean;

   function Directory_Of (File_Name : String) return String;
   --  Abbreviated containing directory with a trailing slash; the current
   --  directory if File_Name is "".

   function Simple_Name (File_Name : String) return String;

   function Complete (Input : String) return String_Vectors.Vector;
   --  Existing names starting with Input; directories get a trailing '/'.

end File_Names;
