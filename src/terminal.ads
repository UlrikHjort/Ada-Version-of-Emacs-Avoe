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

--  Low level terminal access: raw mode, window size, byte input and
--  buffered output of escape sequences.

package Terminal is

   Not_A_Terminal : exception;
   Input_Closed   : exception;

   procedure Initialize;
   --  Enter raw mode and the alternate screen.

   procedure Finalize;
   --  Restore the terminal.  Safe to call more than once.

   procedure Suspend;
   --  Restore the terminal, stop the process (like C-z in a shell) and
   --  re-enter raw mode when continued.

   procedure Get_Size (Rows, Cols : out Positive);

   function Read_Byte (Timeout_Ms : Integer) return Integer;
   --  A byte 0 .. 255, -1 on timeout, -2 when interrupted by a signal.
   --  A negative timeout blocks.  Raises Input_Closed at end of input.

   function Take_Resized return Boolean;
   --  True (once) if the window was resized since the last call.

   function Input_Pending return Boolean;

   function Poll_Quit return Boolean;
   --  Read the input that is already available, without blocking.  True
   --  if it contained C-g (all pending input is then discarded); otherwise
   --  the bytes are kept for Read_Byte.

   procedure Put (S : String);
   --  Append to the output buffer.

   procedure Flush;

end Terminal;
