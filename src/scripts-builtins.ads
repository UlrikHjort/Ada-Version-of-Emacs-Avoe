-- ***************************************************************************
--                          Avoe - Scripts.Builtins
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

--  The editor API available to scripts.

with Scripts.Values; use Scripts.Values;
with String_Vectors;

package Scripts.Builtins is

   Builtin_Error : exception;
   --  Raised by built-ins; the interpreter adds the source position.

   type Arg_Array is array (Positive range <>) of Value;
   --  One element per parameter; omitted optional arguments are None.

   type Builtin_Func is access function (Args : Arg_Array) return Value;

   type Builtin_Info is record
      Func     : Builtin_Func;
      Params   : String_Vectors.Vector;
      Required : Natural := 0;
   end record;

   procedure Register_All;

   function Find (Name : String; Info : out Builtin_Info) return Boolean;

   procedure Run_Editor_Command (Name : String; Count : Positive; Count_Given : Boolean);
   --  Run a registered editor command as if typed with prefix argument Count.

end Scripts.Builtins;
