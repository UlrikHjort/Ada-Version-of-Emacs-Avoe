-- ***************************************************************************
--                              Avoe - Terminal
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

with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;          use Interfaces.C;
with System;

package body Terminal is

   ESC : constant Character := Ada.Characters.Latin_1.ESC;

   Output        : Unbounded_String;
   Active        : Boolean := False;
   Pending_Input : Unbounded_String;  --  Bytes read ahead by Poll_Quit

   function C_Raw_On return int
     with Import, Convention => C, External_Name => "avoe_term_raw_on";
   procedure C_Raw_Off
     with Import, Convention => C, External_Name => "avoe_term_raw_off";
   procedure C_Install_Winch
     with Import, Convention => C, External_Name => "avoe_term_install_winch";
   procedure C_Size (Rows, Cols : out int)
     with Import, Convention => C, External_Name => "avoe_term_size";
   function C_Read_Byte (Timeout_Ms : int) return int
     with Import, Convention => C, External_Name => "avoe_term_read_byte";
   function C_Take_Resized return int
     with Import, Convention => C, External_Name => "avoe_term_take_resized";
   function C_Input_Pending return int
     with Import, Convention => C, External_Name => "avoe_term_input_pending";
   function C_Write (Buf : System.Address; Len : int) return int
     with Import, Convention => C, External_Name => "avoe_term_write";
   procedure C_Suspend
     with Import, Convention => C, External_Name => "avoe_term_suspend";

   --  Use the alternate screen (like less and vi), so the shell's screen
   --  comes back unchanged on exit
   procedure Enter_Screen is
   begin
      Put (ESC & "[?1049h" & ESC & "[H" & ESC & "[2J");
      Flush;
   end Enter_Screen;

   procedure Leave_Screen is
   begin
      Put (ESC & "[0m" & ESC & "[?25h" & ESC & "[?1049l");
      Flush;
   end Leave_Screen;

   procedure Initialize is
   begin
      if C_Raw_On /= 0 then
         raise Not_A_Terminal;
      end if;
      Active := True;
      C_Install_Winch;
      Enter_Screen;
   end Initialize;

   procedure Finalize is
   begin
      if Active then
         Leave_Screen;
         C_Raw_Off;
         Active := False;
      end if;
   end Finalize;

   procedure Suspend is
   begin
      Leave_Screen;
      C_Suspend;
      Enter_Screen;
   end Suspend;

   procedure Get_Size (Rows, Cols : out Positive) is
      R, C : int;
   begin
      C_Size (R, C);
      Rows := (if R < 1 then 24 else Positive (R));
      Cols := (if C < 1 then 80 else Positive (C));
   end Get_Size;

   function Read_Byte (Timeout_Ms : Integer) return Integer is
   begin
      if Length (Pending_Input) > 0 then
         declare
            B : constant Character := Element (Pending_Input, 1);
         begin
            Delete (Pending_Input, 1, 1);
            return Character'Pos (B);
         end;
      end if;
      declare
         R : constant int := C_Read_Byte (int (Timeout_Ms));
      begin
         --  -1: timeout, -2: interrupted by a signal such as a window
         --  resize, -3: the terminal is gone
         if R = -3 then
            raise Input_Closed;
         end if;
         return Integer (R);
      end;
   end Read_Byte;

   function Take_Resized return Boolean is (C_Take_Resized /= 0);

   function Input_Pending return Boolean is
     (Length (Pending_Input) > 0 or else C_Input_Pending /= 0);

   --  Look for C-g while a long script runs.  Other keys typed meanwhile
   --  are kept in Pending_Input, so Read_Byte still returns them.
   function Poll_Quit return Boolean is
      R : int;
   begin
      loop
         R := C_Read_Byte (0);
         exit when R < 0;
         if R = 7 then
            Pending_Input := Null_Unbounded_String;
            return True;
         end if;
         Append (Pending_Input, Character'Val (R));
      end loop;
      return False;
   end Poll_Quit;

   --  Output is collected and written at once by Flush, so a redisplay
   --  does not flicker
   procedure Put (S : String) is
   begin
      Append (Output, S);
   end Put;

   procedure Flush is
      S : constant String := To_String (Output);
   begin
      Output := Null_Unbounded_String;
      if S'Length > 0 and then C_Write (S'Address, int (S'Length)) < 0 then
         raise Input_Closed;
      end if;
   end Flush;

end Terminal;
