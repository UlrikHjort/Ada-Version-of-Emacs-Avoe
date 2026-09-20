-- ***************************************************************************
--                          Avoe - Compile_Commands
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
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Buffer_List;
with Buffers;       use Buffers;
with Commands;      use Commands;
with File_Commands;
with File_Names;
with Minibuffer;    use Minibuffer;
with Modes;
with Processes;
with Syntax;
with Utils;         use Utils;
with Windows;

package body Compile_Commands is

   package L1 renames Ada.Characters.Latin_1;

   Buffer_Name   : constant String := "*compilation*";
   Proc          : Processes.Process;
   Last_Command  : Unbounded_String;
   Directory     : Unbounded_String;  --  With a trailing '/'
   Current_Error : Integer := -1;     --  Line start of the last visited error

   function Comp_Buffer return Buffer_Access is (Buffer_List.Find (Buffer_Name));

   function Running return Boolean is (Processes.Running (Proc));

   --  Put point of every window showing B (and B itself) at Pos
   procedure Show_Position (B : Buffer_Access; Pos : Natural) is
   begin
      for I in 1 .. Windows.Count loop
         if Windows.Get (I).Buf = B then
            Windows.Get (I).Point := Pos;
         end if;
      end loop;
      B.Point := Pos;
   end Show_Position;

   procedure Append_Output (Text : String) is
      B : constant Buffer_Access := Comp_Buffer;
   begin
      if B = null then
         return;
      end if;
      declare
         Old_End : constant Natural := Length (B.all);
         Saved   : constant Natural := B.Point;
      begin
         --  Read-only for the user, not for the output
         B.Read_Only := False;
         B.Point := Old_End;
         Insert (B.all, Text);
         B.Read_Only := True;
         B.Modified := False;
         B.Point := (if Saved = Old_End then Length (B.all) else Saved);
         --  Windows that were at the end follow the output
         for I in 1 .. Windows.Count loop
            declare
               W : constant Windows.Window_Access := Windows.Get (I);
            begin
               if W.Buf = B and then W.Point = Old_End then
                  W.Point := Length (B.all);
               end if;
            end;
         end loop;
      end;
   end Append_Output;

   --  The last command, else make -k with a Makefile, else gprbuild with the
   --  first project file found
   function Default_Command (Dir : String) return String is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if Length (Last_Command) > 0 then
         return To_String (Last_Command);
      elsif Ada.Directories.Exists (Dir & "Makefile")
        or else Ada.Directories.Exists (Dir & "makefile")
      then
         return "make -k";
      end if;
      Start_Search (Search, Dir, "*.gpr", (Ordinary_File => True, others => False));
      if More_Entries (Search) then
         Get_Next_Entry (Search, Item);
         End_Search (Search);
         return "gprbuild -P " & Simple_Name (Item);
      end if;
      End_Search (Search);
      return "make -k";
   exception
      when others =>
         return "make -k";
   end Default_Command;

   function Current_Directory return String is
     (File_Names.Expand (File_Names.Directory_Of (To_String (Windows.Current_Buffer.File_Name))));

   procedure Start (Command : String) is
      Dir : constant String := Current_Directory;
      B   : Buffer_Access := Comp_Buffer;
      Ok  : Boolean;
   begin
      if Running then
         if not Batch_Mode and then Ask ("A compilation is running; kill it?") /= Yes then
            return;
         end if;
         Processes.Kill (Proc);
         declare
            Code : constant Integer := Processes.Finish (Proc);
            pragma Unreferenced (Code);
         begin
            null;
         end;
      end if;

      Last_Command := To_Unbounded_String (Command);
      Directory := To_Unbounded_String (Dir);
      Current_Error := -1;

      if B = null then
         B := Buffer_List.Create (Buffer_Name);
      end if;
      B.Read_Only := False;
      B.Undo_Enabled := False;
      Erase (B.all);
      Modes.Set_Mode (B, Compilation_Mode);
      Insert (B.all, "-*- directory: " & File_Names.Abbreviate (Dir) & " -*-" & L1.LF
              & Command & L1.LF & L1.LF);
      B.Read_Only := True;
      B.Modified := False;
      Windows.Pop_To_Buffer (B);

      --  The command runs in the background: the command loop calls
      --  Collect_Output while it waits for keys
      Processes.Spawn (Command, Dir, Proc, Ok);
      if Ok then
         Message ("Compiling: " & Command);
      else
         Append_Output ("Compilation could not be started" & L1.LF);
         Message ("Compilation could not be started");
      end if;
   end Start;

   procedure Collect_Output (Keyboard : out Boolean) is
      Output : Boolean;
      At_End : Boolean;
      Text   : Unbounded_String;
   begin
      Processes.Wait_Input (Proc, 1000, Keyboard, Output);
      if not Output then
         return;
      end if;
      Processes.Read (Proc, Text, At_End);
      if Length (Text) > 0 then
         Append_Output (To_String (Text));
      end if;
      if At_End then
         declare
            Code   : constant Integer := Processes.Finish (Proc);
            Status : constant String :=
              (if Code = 0 then "Compilation finished"
               else "Compilation exited abnormally with code " & Img (Code));
         begin
            Append_Output (L1.LF & Status & L1.LF);
            Message (Status);
         end;
      end if;
   end Collect_Output;

   procedure Shutdown is
   begin
      if Running then
         Processes.Kill (Proc);
         declare
            Code : constant Integer := Processes.Finish (Proc);
            pragma Unreferenced (Code);
         begin
            null;
         end;
      end if;
   end Shutdown;

   -------------------------------------------------------------------------
   --  Error locations
   -------------------------------------------------------------------------

   function Location_At
     (B      : Buffer;
      S      : Natural;
      File   : out Unbounded_String;
      Line   : out Natural;
      Column : out Natural) return Boolean is
   begin
      return Syntax.Parse_Location
        (Slice (B, S, Natural'Min (Line_End (B, S), S + 1000)), File, Line, Column);
   end Location_At;

   --  File names in messages are relative to the directory the command ran
   --  in.  The file is shown in the other window, next to the messages.
   procedure Visit_Location (File : String; Line, Column : Natural) is
      Full   : constant String :=
        (if File'Length > 0 and then File (File'First) = '/' then File
         else To_String (Directory) & File);
      Target : constant Buffer_Access := File_Commands.Visit_File (Full);
      Ok     : Boolean;
   begin
      if Target = null then
         return;
      end if;
      if Windows.Current_Buffer = Comp_Buffer then
         if Windows.Count = 1 then
            Windows.Split_Current (Ok);
         end if;
         Windows.Other_Window;
      end if;
      File_Commands.Switch_To (Target);
      Target.Point := Pos_Of_Line (Target.all, Positive'Max (1, Line));
      if Column > 0 then
         --  Compilers count columns from 1
         Target.Point := Pos_At_Column (Target.all, Target.Point, Column - 1);
      end if;
   end Visit_Location;

   procedure Go_To_Error (B : Buffer_Access; S : Natural) is
      File   : Unbounded_String;
      Line   : Natural;
      Column : Natural;
   begin
      if Location_At (B.all, S, File, Line, Column) then
         Current_Error := S;
         Show_Position (B, S);
         Visit_Location (To_String (File), Line, Column);
         Message (Slice (B.all, S, Natural'Min (Line_End (B.all, S), S + 300)));
      end if;
   end Go_To_Error;

   procedure Find_Error (Forward : Boolean) is
      B      : constant Buffer_Access := Comp_Buffer;
      File   : Unbounded_String;
      Line   : Natural;
      Column : Natural;
      S      : Natural;
   begin
      if B = null then
         Message ("No compilation buffer");
         return;
      end if;
      --  A new compilation has emptied the buffer since
      if Current_Error > Length (B.all) then
         Current_Error := -1;
      end if;

      if Forward then
         S := (if Current_Error < 0 then 0 else Line_End (B.all, Current_Error) + 1);
         while S < Length (B.all) loop
            if Location_At (B.all, S, File, Line, Column) then
               Go_To_Error (B, S);
               return;
            end if;
            S := Line_End (B.all, S) + 1;
         end loop;
         Message ("No more errors" & (if Running then " yet" else ""));
      else
         S := Natural'Max (Current_Error, 0);
         while S > 0 loop
            S := Line_Start (B.all, S - 1);
            if Location_At (B.all, S, File, Line, Column) then
               Go_To_Error (B, S);
               return;
            end if;
         end loop;
         Message ("No previous error");
      end if;
   end Find_Error;

   -------------------------------------------------------------------------
   --  Commands
   -------------------------------------------------------------------------

   procedure Compile is
      Input : Unbounded_String;
      Ok    : Boolean;
   begin
      Read_String ("Compile command: ", Default_Command (Current_Directory), Input, Ok);
      if Ok and then Length (Input) > 0 then
         Start (To_String (Input));
      end if;
   end Compile;

   procedure Recompile is
   begin
      if Length (Last_Command) = 0 then
         Compile;
      else
         Start (To_String (Last_Command));
      end if;
   end Recompile;

   procedure Kill_Compilation is
   begin
      if Running then
         Processes.Kill (Proc);
         Message ("Killing compilation");
      else
         Message ("No compilation is running");
      end if;
   end Kill_Compilation;

   procedure Next_Error is
   begin
      Find_Error (Forward => True);
   end Next_Error;

   procedure Previous_Error is
   begin
      Find_Error (Forward => False);
   end Previous_Error;

   procedure Compile_Goto_Error is
      B : constant Buffer_Access := Windows.Current_Buffer;
      S : constant Natural := Line_Start (B.all, B.Point);
      File   : Unbounded_String;
      Line   : Natural;
      Column : Natural;
   begin
      if B /= Comp_Buffer or else not Location_At (B.all, S, File, Line, Column) then
         Message ("No error location on this line");
         return;
      end if;
      Go_To_Error (B, S);
   end Compile_Goto_Error;

   procedure Register_All is
   begin
      Register ("compile", Compile'Access);
      Register ("recompile", Recompile'Access);
      Register ("kill_compilation", Kill_Compilation'Access);
      Register ("next_error", Next_Error'Access, Repeatable => True);
      Register ("previous_error", Previous_Error'Access, Repeatable => True);
      Register ("compile_goto_error", Compile_Goto_Error'Access);
   end Register_All;

end Compile_Commands;
