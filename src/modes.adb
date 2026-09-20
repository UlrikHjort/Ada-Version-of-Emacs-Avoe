-- ***************************************************************************
--                                Avoe - Modes
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
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Ada_Indent;
with Commands;   use Commands;
with Keymaps;
with Minibuffer;
with Mode_Defs;
with Scripts;
with String_Vectors;
with Utils;
with Windows;

package body Modes is

   package L1 renames Ada.Characters.Latin_1;

   function Mode_For_File (File_Name : String) return Mode_Kind is
     (Mode_Defs.For_File (File_Name));

   function Mode_Of_Name (Name : String; Found : out Boolean) return Mode_Kind is
      M : constant Natural := Mode_Defs.Find (Name);
   begin
      Found := M > 0;
      return (if Found then M else Fundamental_Mode);
   end Mode_Of_Name;

   function Hook_Name (Mode : Mode_Kind) return String is
     (Mode_Defs.Name (Mode) & "_mode_hook");

   procedure Set_Mode (B : Buffer_Access; Mode : Mode_Kind) is
   begin
      B.Mode := Mode;
      if Commands.Exists (Hook_Name (Mode)) then
         Commands.Run (Hook_Name (Mode));
      end if;
   exception
      when E : Scripts.Script_Error =>
         --  A broken hook in someone's script must not stop a file opening
         Minibuffer.Message ("Error in " & Hook_Name (Mode) & ": "
                             & Ada.Exceptions.Exception_Message (E));
   end Set_Mode;

   procedure Set_Current (Mode : Mode_Kind) is
   begin
      Set_Mode (Windows.Current_Buffer, Mode);
   end Set_Current;

   procedure Cmd_Fundamental_Mode is
   begin
      Set_Current (Fundamental_Mode);
   end Cmd_Fundamental_Mode;

   procedure Cmd_Ada_Mode is
   begin
      Set_Current (Ada_Mode);
   end Cmd_Ada_Mode;

   procedure Cmd_Script_Mode is
   begin
      Set_Current (Script_Mode);
   end Cmd_Script_Mode;

   function Complete_Mode (Input : String) return String_Vectors.Vector is
      Result : String_Vectors.Vector;
   begin
      for N of Mode_Defs.Names loop
         if Utils.Starts_With (N, Mode_Defs.Normalize_Name (Input)) then
            Result.Append (N);
         end if;
      end loop;
      return Result;
   end Complete_Mode;

   procedure Set_Major_Mode is
      Input : Unbounded_String;
      Ok    : Boolean;
      Found : Boolean;
      M     : Mode_Kind;
   begin
      Minibuffer.Read_String ("Mode: ", "", Input, Ok, Complete_Mode'Access);
      if not Ok or else Length (Input) = 0 then
         return;
      end if;
      M := Mode_Of_Name (To_String (Input), Found);
      if Found then
         Set_Current (M);
      else
         Minibuffer.Message ("No mode named " & To_String (Input));
      end if;
   end Set_Major_Mode;

   --  The built-in indenter knows Ada and Avoe script; modes written as
   --  scripts bind their own TAB and RET commands
   function Indents (B : Buffer) return Boolean is (B.Mode in Ada_Mode | Script_Mode);

   procedure Indent_Line is
      B : Buffer renames Windows.Current_Buffer.all;
   begin
      if Indents (B) then
         Ada_Indent.Indent_Line (B);
      else
         Insert (B, (1 => L1.HT));
      end if;
   end Indent_Line;

   procedure Reindent_Then_Newline_And_Indent is
      B : Buffer renames Windows.Current_Buffer.all;
   begin
      if not Indents (B) then
         Insert (B, (1 => L1.LF));
         return;
      end if;
      Ada_Indent.Indent_Line (B);
      declare
         S : constant Natural := Line_Start (B, B.Point);
      begin
         --  Leave no trailing blanks on the line
         while B.Point > S and then Char_At (B, B.Point - 1) in ' ' | L1.HT loop
            Delete (B, B.Point - 1, B.Point);
         end loop;
      end;
      Insert (B, (1 => L1.LF));
      Ada_Indent.Indent_Line (B);
   end Reindent_Then_Newline_And_Indent;

   procedure Register_All is
      use Keymaps;
   begin
      Register ("fundamental_mode", Cmd_Fundamental_Mode'Access);
      Register ("ada_mode", Cmd_Ada_Mode'Access);
      Register ("script_mode", Cmd_Script_Mode'Access);
      Register ("set_major_mode", Set_Major_Mode'Access);
      Register ("indent_line", Indent_Line'Access, Repeatable => True);
      Register ("reindent_then_newline_and_indent",
                Reindent_Then_Newline_And_Indent'Access, Repeatable => True);

      for M in Ada_Mode .. Script_Mode loop
         Bind (Mode_Map (M), "TAB", "indent_line");
         Bind (Mode_Map (M), "RET", "reindent_then_newline_and_indent");
         Bind (Mode_Map (M), "C-c C-c", "compile");
         Bind (Mode_Map (M), "C-c C-o", "find_other_file");
         Bind (Mode_Map (M), "C-c C-f", "format_buffer");
      end loop;

      Bind (Mode_Map (Compilation_Mode), "RET", "compile_goto_error");
      Bind (Mode_Map (Compilation_Mode), "g", "recompile");
      Bind (Mode_Map (Compilation_Mode), "C-c C-k", "kill_compilation");
   end Register_All;

end Modes;
