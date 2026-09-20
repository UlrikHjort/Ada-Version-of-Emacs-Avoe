-- ***************************************************************************
--                         Avoe - Scripts.Interpreter
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

--  Tree-walking interpreter for Avoe script.

package Scripts.Interpreter is

   type Quit_Check is access function return Boolean;

   Interrupt_Check : Quit_Check := null;
   --  Polled regularly; returning True aborts the running script ("Quit").

   procedure Execute_Source (Source : String; File_Name : String);
   --  Parse and run a script.  Subprograms it declares stay defined.

   procedure Load_File (File_Name : String; Display_Name : String := "");

   function Evaluate (Source : String; File_Name : String := "eval") return String;
   --  If Source ends with ';' it is run as statements and "" is returned;
   --  otherwise it is evaluated as an expression and the value is returned
   --  as a literal ("" if it has no value).

   procedure Run_Command (Name : String);
   --  Call the script procedure registered as editor command Name.

   function Is_Defined (Name : String) return Boolean;

   function Current_Exception_Name return String;
   function Current_Exception_Message return String;
   --  Of the exception being handled, or "" outside exception handlers.

end Scripts.Interpreter;
