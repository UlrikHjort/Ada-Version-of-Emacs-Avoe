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

--  The set of all buffers, in most-recently-used order.

with Buffers; use Buffers;
with String_Vectors;

package Buffer_List is

   function Create (Name : String) return Buffer_Access;
   --  A new empty buffer.  The name is made unique ("foo<2>") if needed.

   function Find (Name : String) return Buffer_Access;
   function Find_File (File_Name : String) return Buffer_Access;
   --  null if not found

   procedure Remove (B : in out Buffer_Access);
   --  Delete and free the buffer.  No window may still show it.

   function Count return Natural;
   function Get (Index : Positive) return Buffer_Access;

   procedure Touch (B : Buffer_Access);
   --  Mark as most recently used.

   function Unique_Name (Base : String; Except : Buffer_Access := null) return String;

   function Other_Buffer (Than : Buffer_Access) return Buffer_Access;
   --  Most recently used buffer other than Than, or null.

   function Complete_Name (Input : String) return String_Vectors.Vector;

end Buffer_List;
