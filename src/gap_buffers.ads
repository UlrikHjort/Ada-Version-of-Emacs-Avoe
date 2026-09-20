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

--  A gap buffer of bytes.  Positions are 0-based logical offsets; a
--  position P lies between byte P-1 and byte P.

with Ada.Finalization;

package Gap_Buffers is

   type Gap_Buffer is new Ada.Finalization.Limited_Controlled with private;

   function Length (B : Gap_Buffer) return Natural;

   function Element (B : Gap_Buffer; Pos : Natural) return Character
     with Pre => Pos < Length (B);

   function Slice (B : Gap_Buffer; From, To : Natural) return String
     with Pre => From <= To and then To <= Length (B);
   --  The bytes in [From, To).  Intended for moderately sized ranges.

   procedure Insert (B : in out Gap_Buffer; Pos : Natural; Text : String)
     with Pre => Pos <= Length (B);

   procedure Delete (B : in out Gap_Buffer; From, To : Natural)
     with Pre => From <= To and then To <= Length (B);

   procedure Clear (B : in out Gap_Buffer);

private

   type Storage is array (Natural range <>) of Character;
   type Storage_Access is access Storage;

   type Gap_Buffer is new Ada.Finalization.Limited_Controlled with record
      Data      : Storage_Access := null;
      Gap_Start : Natural := 0;  --  First index of the gap
      Gap_End   : Natural := 0;  --  One past the last index of the gap
   end record;

   overriding procedure Finalize (B : in out Gap_Buffer);

end Gap_Buffers;
