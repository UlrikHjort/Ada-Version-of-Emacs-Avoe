-- ***************************************************************************
--                             Avoe - Minibuffer
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

--  The echo area: messages, prompts, questions and completion.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Keys;                  use Keys;
with String_Vectors;

package Minibuffer is

   type Answer is (Yes, No, Cancel);

   Batch_Mode : Boolean := False;
   --  No terminal: messages go to standard output and asking for input
   --  raises Not_Interactive.

   Not_Interactive : exception;

   type Completer is access function (Input : String) return String_Vectors.Vector;

   procedure Message (Text : String);
   function Current_Message return String;
   procedure Clear_Message;

   procedure Redisplay;
   --  Render the screen with the current message.

   function Read_Key_Echo (Echo : String; Cursor_At_End : Boolean := False) return Key;
   --  Show Echo and read a key, handling resizes.

   procedure Read_String
     (Prompt   : String;
      Initial  : String;
      Result   : out Unbounded_String;
      Ok       : out Boolean;
      Complete : Completer := null;
      History  : String := "");
   --  Line input with Emacs editing keys: C-a/C-e/C-b/C-f and arrows move,
   --  M-b/M-f move by words, DEL/C-d delete, M-DEL deletes a word, C-k
   --  kills to the end, C-u clears, C-y yanks, TAB completes, M-p/M-n (or
   --  Up/Down) browse earlier input, RET accepts, C-g aborts (Ok = False).
   --  Inputs are remembered per History name (by default, the prompt).

   function Ask (Question : String) return Answer;
   --  y / n / C-g

   function Ask_Yes_Or_No (Question : String) return Answer;
   --  The answer must be typed out: "yes" or "no" and RET (C-g cancels).
   --  For questions where a single stray key should not decide.

end Minibuffer;
