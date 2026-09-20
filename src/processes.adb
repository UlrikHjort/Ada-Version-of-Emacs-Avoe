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

with Interfaces.C; use Interfaces.C;
with System;

package body Processes is

   procedure C_Spawn (Cmd, Dir : char_array; Pid, Fd : out int)
     with Import, Convention => C, External_Name => "avoe_spawn";
   function C_Poll (Fd : int; Timeout : int) return int
     with Import, Convention => C, External_Name => "avoe_poll_input";
   function C_Read_Fd (Fd : int; Buf : System.Address; Len : int) return int
     with Import, Convention => C, External_Name => "avoe_read_fd";
   function C_Wait (Pid : int) return int
     with Import, Convention => C, External_Name => "avoe_wait_process";
   procedure C_Kill (Pid : int)
     with Import, Convention => C, External_Name => "avoe_kill_process";
   procedure C_Close (Fd : int)
     with Import, Convention => C, External_Name => "avoe_close_fd";

   procedure Spawn (Command, Directory : String; P : out Process; Ok : out Boolean) is
      Pid, Fd : int;
   begin
      C_Spawn (To_C (Command), To_C (Directory), Pid, Fd);
      Ok := Fd >= 0;
      P := (if Ok then (Pid => Integer (Pid), Fd => Integer (Fd)) else (Pid => -1, Fd => -1));
   end Spawn;

   procedure Wait_Input
     (P          : Process;
      Timeout_Ms : Integer;
      Keyboard   : out Boolean;
      Output     : out Boolean)
   is
      R : constant int := C_Poll (int (P.Fd), int (Timeout_Ms));
   begin
      --  R is a bit mask: 1 keyboard, 2 process output.  An error counts as
      --  keyboard input, so that the caller wakes up and looks.
      Keyboard := R < 0 or else R mod 2 = 1;
      Output := R > 0 and then (R / 2) mod 2 = 1;
   end Wait_Input;

   --  Take the output that is available now (N < 0: nothing more for the
   --  moment, 0: the process closed its output).  At most about 256 KB at a
   --  time, so that a very chatty command cannot freeze the editor.
   procedure Read (P : Process; Text : out Unbounded_String; At_End : out Boolean) is
      Buf : String (1 .. 4096);
      N   : int;
   begin
      Text := Null_Unbounded_String;
      At_End := False;
      loop
         N := C_Read_Fd (int (P.Fd), Buf'Address, int (Buf'Length));
         if N = 0 then
            At_End := True;
            exit;
         elsif N < 0 then
            exit;
         end if;
         Append (Text, Buf (1 .. Integer (N)));
         exit when Length (Text) > 256_000;
      end loop;
   end Read;

   --  Close the pipe and wait for the process; its exit code, or -1
   function Finish (P : in out Process) return Integer is
      Code : Integer := -1;
   begin
      if P.Fd >= 0 then
         C_Close (int (P.Fd));
      end if;
      if P.Pid > 0 then
         Code := Integer (C_Wait (int (P.Pid)));
      end if;
      P := (Pid => -1, Fd => -1);
      return Code;
   end Finish;

   procedure Kill (P : Process) is
   begin
      if P.Pid > 0 then
         C_Kill (int (P.Pid));
      end if;
   end Kill;

end Processes;
