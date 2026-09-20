-- ***************************************************************************
--                              Avoe - Commands
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

--  The command registry and the context commands run in.
--
--  Commands are named (Ada style, e.g. "find_file") and keys are bound to
--  names, so built-in commands and script commands are interchangeable.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Keys;
with String_Vectors;

package Commands is

   type Command_Proc is access procedure;

   Unknown_Command : exception;

   function Normalize (Name : String) return String;
   --  Lower case, '-' becomes '_': "Find-File" -> "find_file".

   procedure Register
     (Name       : String;
      Proc       : Command_Proc;
      Repeatable : Boolean := False);
   --  Repeatable commands run N times with a prefix argument.

   procedure Register_Script (Name : String);
   --  A command implemented by a script procedure of the same name.
   --  Replaces a built-in command with that name.

   type Script_Runner is access procedure (Name : String);

   Run_Script_Command : Script_Runner := null;
   --  Set by the script system.

   function Exists (Name : String) return Boolean;
   function Is_Repeatable (Name : String) return Boolean;

   procedure Run (Name : String);

   function Complete (Input : String) return String_Vectors.Vector;
   --  Command names starting with Input.

   --  Context for the command being executed

   type Command_Class is
     (Class_Other, Class_Vertical, Class_Kill, Class_Yank, Class_Undo,
      Class_Insert);

   Last_Class     : Command_Class := Class_Other;
   This_Class     : Command_Class := Class_Other;
   Prefix_Arg     : Positive := 1;
   Arg_Given      : Boolean := False;
   Last_Key       : Keys.Key;
   Quit_Requested : Boolean := False;
   Confirm_Exit   : Boolean := False;
   --  C-x C-c asks "leave anyway? (yes or no)" while a buffer that is not
   --  read-only has unsaved changes (Set_Confirm_Exit in a script)
   Startup_Screen : Boolean := True;
   --  Show the *About* window at startup (Set_Startup_Screen in a script)
   Last_Command   : Unbounded_String;  --  Name of the previous command
   This_Command   : Unbounded_String;  --  Name of the running command

end Commands;
