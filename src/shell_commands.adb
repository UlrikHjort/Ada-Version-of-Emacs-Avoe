-- ***************************************************************************
--                           Avoe - Shell_Commands
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
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Buffers;          use Buffers;
with Commands;         use Commands;
with Compile_Commands;
with File_Commands;
with File_IO;
with File_Names;
with Minibuffer;       use Minibuffer;
with Mode_Defs;
with Paths;
with Processes;
with Terminal;
with Utils;            use Utils;
with Windows;

package body Shell_Commands is

   package L1 renames Ada.Characters.Latin_1;

   function Directory_Of_Current return String is
     (File_Names.Expand
        (File_Names.Directory_Of (To_String (Windows.Current_Buffer.File_Name))));

   --  Quote for /bin/sh: in single quotes, with ' written as '\''
   function Shell_Quote (S : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("'");
   begin
      for C of S loop
         if C = ''' then
            Append (Result, "'\''");
         else
            Append (Result, C);
         end if;
      end loop;
      Append (Result, "'");
      return To_String (Result);
   end Shell_Quote;

   --  Run Command to completion, collecting its output.  C-g kills it.
   procedure Run
     (Command   : String;
      Directory : String;
      Output    : out Unbounded_String;
      Code      : out Integer;
      Started   : out Boolean)
   is
      P        : Processes.Process;
      Keyboard : Boolean;
      Ready    : Boolean;
      At_End   : Boolean;
      Chunk    : Unbounded_String;
      Killed   : Boolean := False;
   begin
      Output := Null_Unbounded_String;
      Code := -1;
      Processes.Spawn (Command, Directory, P, Started);
      if not Started then
         return;
      end if;
      loop
         Processes.Wait_Input (P, 200, Keyboard, Ready);
         if Ready then
            Processes.Read (P, Chunk, At_End);
            Append (Output, Chunk);
            exit when At_End;
         end if;
         if Keyboard and then not Killed and then not Batch_Mode and then Terminal.Poll_Quit then
            Processes.Kill (P);
            Killed := True;
         end if;
      end loop;
      Code := Processes.Finish (P);
      if Killed then
         Message ("Quit");
      end if;
   end Run;

   function Command_Output (Command : String) return String is
      Output  : Unbounded_String;
      Code    : Integer;
      Started : Boolean;
      pragma Warnings (Off, Code);
      pragma Warnings (Off, Started);
   begin
      Run (Command, Directory_Of_Current, Output, Code, Started);
      return To_String (Output);
   end Command_Output;

   procedure Write_Text (Path : String; Text : String) is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      String'Write (Stream (F), Text);
      Close (F);
   end Write_Text;

   procedure Execute (Command : String; Into_Buffer : Boolean; On_Region : Boolean) is
      B          : constant Buffer_Access := Windows.Current_Buffer;
      Input_File : constant String := Paths.State_Directory & "/shell-region-input";
      From       : constant Natural := Natural'Min (B.Point, B.Mark);
      To         : constant Natural := Natural'Max (B.Point, B.Mark);
      Output     : Unbounded_String;
      Code       : Integer;
      Started    : Boolean;
   begin
      --  The command reads the region from a temporary file, as commands
      --  are started without an input pipe
      if On_Region then
         File_IO.Make_Directories (Paths.State_Directory);
         Write_Text (Input_File, To_String (Text_Of (B.all, From, To)));
         Run ("(" & Command & ") < " & Shell_Quote (Input_File), Directory_Of_Current,
              Output, Code, Started);
         File_IO.Delete (Input_File);
      else
         Run (Command, Directory_Of_Current, Output, Code, Started);
      end if;

      if not Started then
         Message ("Could not run /bin/sh");
         return;
      end if;

      declare
         Text : constant String := To_String (Output);
         NL   : constant Natural := Ada.Strings.Fixed.Index (Text, (1 => L1.LF));
      begin
         if Into_Buffer then
            if On_Region then
               Delete (B.all, From, To);
               B.Point := From;
            end if;
            declare
               Start : constant Natural := B.Point;
            begin
               Insert (B.all, Output);
               B.Mark := B.Point;
               B.Mark_Set := True;
               B.Point := Start;
            end;
            if Code /= 0 then
               Message ("Shell command failed with code " & Img (Code));
            end if;
         --  As in Emacs: no output or one line is a message, more goes to a
         --  buffer
         elsif Text = "" then
            Message (if Code = 0 then "(Shell command succeeded with no output)"
                     else "(Shell command failed with code " & Img (Code) & " and no output)");
         elsif NL = 0 or else NL = Text'Last then
            Message (Text (Text'First .. (if NL = 0 then Text'Last else NL - 1))
                     & (if Code = 0 then "" else "  (exit code " & Img (Code) & ")"));
         else
            File_Commands.Show_Special ("*Shell Command Output*", Output);
            if Code /= 0 then
               Message ("Shell command failed with code " & Img (Code));
            end if;
         end if;
      end;
   end Execute;

   procedure Shell_Command is
      Insert_Output : constant Boolean := Arg_Given;
      Input         : Unbounded_String;
      Ok            : Boolean;
   begin
      Read_String ((if Insert_Output then "Shell command (insert output): "
                    else "Shell command: "), "", Input, Ok, History => "shell");
      if Ok and then Length (Input) > 0 then
         Execute (To_String (Input), Into_Buffer => Insert_Output, On_Region => False);
      end if;
   end Shell_Command;

   procedure Shell_Command_On_Region is
      Replace : constant Boolean := Arg_Given;
      Input   : Unbounded_String;
      Ok      : Boolean;
   begin
      if not Windows.Current_Buffer.Mark_Set then
         Message ("The mark is not set now, so there is no region");
         return;
      end if;
      Read_String ((if Replace then "Shell command on region (replace): "
                    else "Shell command on region: "), "", Input, Ok, History => "shell");
      if Ok and then Length (Input) > 0 then
         Execute (To_String (Input), Into_Buffer => Replace, On_Region => True);
      end if;
   end Shell_Command_On_Region;

   procedure Grep is
      Input : Unbounded_String;
      Ok    : Boolean;
   begin
      Read_String ("Run grep: ", "grep -rnH --color=never -e ", Input, Ok, History => "grep");
      if Ok and then Length (Input) > 0 then
         Compile_Commands.Start (To_String (Input));
      end if;
   end Grep;

   -------------------------------------------------------------------------
   --  Formatting
   -------------------------------------------------------------------------

   function Replace_All (Source, Pattern, By : String) return String is
      Result : Unbounded_String;
      I      : Integer := Source'First;
   begin
      while I <= Source'Last loop
         if I + Pattern'Length - 1 <= Source'Last
           and then Source (I .. I + Pattern'Length - 1) = Pattern
         then
            Append (Result, By);
            I := I + Pattern'Length;
         else
            Append (Result, Source (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Replace_All;

   function File_Text (Path : String) return String is
      Temp : Buffer;
      Msg  : Unbounded_String;
      Ok   : Boolean;
   begin
      Load (Temp, Path, Msg, Ok);
      return (if Ok then To_String (Text_Of (Temp, 0, Length (Temp))) else "");
   end File_Text;

   --  Run the mode's formatter on a copy of the buffer.  Only standard
   --  output becomes the new text, and only if the formatter succeeds.
   procedure Format_Buffer is
      B        : constant Buffer_Access := Windows.Current_Buffer;
      Template : constant String := To_String (Mode_Defs.Get (B.Mode).Formatter);
      Name     : constant String := File_Names.Simple_Name (To_String (B.File_Name));
      Dot      : constant Natural :=
        Ada.Strings.Fixed.Index (Name, ".", Ada.Strings.Backward);
      --  The copy keeps the file's extension: some formatters use it to
      --  decide the language
      Input    : constant String :=
        Paths.State_Directory & "/format-input" & (if Dot > 0 then Name (Dot .. Name'Last) else "");
      Errors   : constant String := Paths.State_Directory & "/format-errors";
      Output   : Unbounded_String;
      Code     : Integer;
      Started  : Boolean;
   begin
      if Template = "" then
         Message ("No formatter is defined for " & Mode_Defs.Title (B.Mode) & " mode");
         return;
      end if;
      File_IO.Make_Directories (Paths.State_Directory);
      Write_Text (Input, To_String (Text_Of (B.all, 0, Length (B.all))));
      Run ("(" & Replace_All (Template, "%f", Shell_Quote (Input)) & ") 2> " & Shell_Quote (Errors),
           Directory_Of_Current, Output, Code, Started);
      File_IO.Delete (Input);

      if not Started then
         Message ("Could not run /bin/sh");
      --  No output for a non-empty buffer is a failure too: never replace
      --  the text with nothing
      elsif Code /= 0 or else (Length (Output) = 0 and then Length (B.all) > 0) then
         declare
            Error_Text : constant String := File_Text (Errors);
            NL         : constant Natural := Ada.Strings.Fixed.Index (Error_Text, (1 => L1.LF));
         begin
            Message ("Formatter failed with code " & Img (Code)
                     & (if Error_Text = "" then ""
                        else ": " & Error_Text (Error_Text'First
                                              .. (if NL = 0 then Error_Text'Last else NL - 1))));
            if NL > 0 and then NL < Error_Text'Last then
               File_Commands.Show_Special ("*Format Errors*", To_Unbounded_String (Error_Text));
            end if;
         end;
      elsif Output = Text_Of (B.all, 0, Length (B.all)) then
         Message ("Already formatted");
      else
         --  Keep the cursor on the same line and column
         declare
            Line   : constant Positive := Line_Number (B.all, B.Point);
            Column : constant Natural := Column_Of (B.all, B.Point);
         begin
            Delete (B.all, 0, Length (B.all));
            B.Point := 0;
            Insert (B.all, Output);
            B.Point := Pos_At_Column (B.all, Pos_Of_Line (B.all, Line), Column);
            Message ("Formatted");
         end;
      end if;
      File_IO.Delete (Errors);
   end Format_Buffer;

   procedure Register_All is
   begin
      Register ("format_buffer", Format_Buffer'Access);
      Register ("shell_command", Shell_Command'Access);
      Register ("shell_command_on_region", Shell_Command_On_Region'Access);
      Register ("grep", Grep'Access);
   end Register_All;

end Shell_Commands;
