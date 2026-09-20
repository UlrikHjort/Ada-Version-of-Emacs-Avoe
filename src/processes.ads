-- ***************************************************************************
--                              Avoe - Processes
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

--  Subprocesses whose output is collected through a pipe (used by the
--  compile buffer).

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Processes is

   type Process is record
      Pid : Integer := -1;
      Fd  : Integer := -1;
   end record;

   function Running (P : Process) return Boolean is (P.Fd >= 0);

   procedure Spawn (Command, Directory : String; P : out Process; Ok : out Boolean);
   --  Run Command with /bin/sh in Directory; stdout and stderr are captured.

   procedure Wait_Input
     (P          : Process;
      Timeout_Ms : Integer;
      Keyboard   : out Boolean;
      Output     : out Boolean);
   --  Wait until a key is typed, the process writes (or ends), or the
   --  timeout expires.  Keyboard is also True after a window resize.

   procedure Read (P : Process; Text : out Unbounded_String; At_End : out Boolean);
   --  Everything available now.  At_End when the output is closed.

   function Finish (P : in out Process) return Integer;
   --  Close the pipe and reap the process; its exit code.

   procedure Kill (P : Process);

end Processes;
