-- ***************************************************************************
--                               Avoe - Editor
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

with Ada.Calendar.Formatting;
with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Buffer_List;
with File_Names;
with Paths;
with Version_Info;
with Buffers;         use Buffers;
with Auto_Save;
with Compile_Commands;
with File_IO;
with Modes;
with Processes;
with Commands;        use Commands;
with Display;
with Edit_Commands;
with File_Commands;
with Keymaps;         use Keymaps;
with Keys;            use Keys;
with Minibuffer;      use Minibuffer;
with Script_Commands;
with Scripts;
with Search_Commands;
with Shell_Commands;
with Terminal;
with Utils;           use Utils;
with Windows;

package body Editor is

   package L1 renames Ada.Characters.Latin_1;

   Command_Start : Natural := 0;
   --  While a keyboard macro is recorded: the number of keys recorded
   --  before the current command, so C-x ) is not part of the macro

   Executing_Macro : Boolean := False;

   Insert_Run : Natural := 0;  --  Self-inserts in the current undo group
   Max_Insert_Run : constant := 20;

   -------------------------------------------------------------------------
   --  Running commands
   -------------------------------------------------------------------------

   procedure Execute_Command (Name : String) is
      B     : constant Buffer_Access := Windows.Current_Buffer;
      Times : constant Positive :=
        (if Is_Repeatable (Name) then Prefix_Arg else 1);
   begin
      if Name = "self_insert"
        and then Last_Class = Class_Insert
        and then Insert_Run < Max_Insert_Run
      then
         Insert_Run := Insert_Run + 1;
      else
         Add_Undo_Boundary (B.all);
         Insert_Run := (if Name = "self_insert" then 1 else 0);
      end if;

      This_Class := Class_Other;
      This_Command := To_Unbounded_String (Name);
      for I in 1 .. Times loop
         if I > 1 then
            Last_Class := This_Class;
         end if;
         Run (Name);
         exit when Current_Message /= "" or else Quit_Requested;
      end loop;
   end Execute_Command;

   function Meta_Of_Esc (K : Key; Echo : String) return Key is
      Next : Key;
   begin
      if K.Code = Esc and then not K.Meta and then not K.Ctrl then
         Next := Read_Key_Echo (Echo & "ESC-");
         Next.Meta := True;
         return Next;
      end if;
      return K;
   end Meta_Of_Esc;

   procedure Read_Universal_Argument (Next : out Key) is
      Value       : Natural := 4;
      Digits_Seen : Boolean := False;
      K           : Key;
   begin
      loop
         K := Read_Key_Echo ("C-u " & (if Digits_Seen then Img (Value) & " " else "")
                             & "-");
         if not K.Meta and then K.Code = Ctl_U and then not Digits_Seen then
            Value := Natural'Min (Value * 4, 1_000_000);
         elsif not K.Meta
           and then K.Code in Character'Pos ('0') .. Character'Pos ('9')
         then
            if not Digits_Seen then
               Value := 0;
               Digits_Seen := True;
            end if;
            Value := Natural'Min (Value * 10 + (K.Code - Character'Pos ('0')), 1_000_000);
         else
            Next := K;
            exit;
         end if;
      end loop;
      Prefix_Arg := Positive'Max (1, Value);
      Arg_Given := True;
   end Read_Universal_Argument;

   --  Look K up in the mode map first, then in the global map.  After a
   --  prefix key both maps have advanced to their sub-maps (or null).
   function Lookup_Key
     (Mode_Now, Global_Now : in out Keymap_Access; K : Key) return Binding
   is
      Unbound_Key : constant Binding := (Kind => Unbound, others => <>);
      M : constant Binding := (if Mode_Now = null then Unbound_Key else Lookup (Mode_Now, K));
      G : constant Binding := (if Global_Now = null then Unbound_Key else Lookup (Global_Now, K));
   begin
      if M.Kind /= Unbound then
         if M.Kind = Prefix then
            Mode_Now := M.Map;
            Global_Now := (if G.Kind = Prefix then G.Map else null);
         end if;
         return M;
      end if;
      if G.Kind = Prefix then
         Mode_Now := null;
         Global_Now := G.Map;
      end if;
      return G;
   end Lookup_Key;

   procedure Dispatch (First : Key) is
      K      : Key := First;
      Mode_M : Keymap_Access := Mode_Map (Windows.Current_Buffer.Mode);
      Map    : Keymap_Access := Global_Map;
      Seq : Unbounded_String;
      Bnd : Binding;
   begin
      Prefix_Arg := 1;
      Arg_Given := False;

      loop
         K := Meta_Of_Esc (K, (if Length (Seq) > 0 then To_String (Seq) & " " else ""));
         Bnd := Lookup_Key (Mode_M, Map, K);
         if Length (Seq) > 0 then
            Append (Seq, " ");
         end if;
         Append (Seq, Describe (K));

         case Bnd.Kind is
            when Prefix =>
               K := Read_Key_Echo (To_String (Seq) & "-");
               if K.Code = Ctl_G and then not K.Meta then
                  Message ("Quit");
                  return;
               end if;

            when Command =>
               declare
                  Name : constant String := To_String (Bnd.Name);
               begin
                  if Name = "universal_argument" then
                     Read_Universal_Argument (K);
                     Map := Global_Map;
                     Mode_M := Mode_Map (Windows.Current_Buffer.Mode);
                     Seq := Null_Unbounded_String;
                  else
                     Last_Key := K;
                     if Exists (Name) then
                        Execute_Command (Name);
                     else
                        Message (Name & " is not a known command");
                     end if;
                     return;
                  end if;
               end;

            when Unbound =>
               if Map = Global_Map and then Is_Self_Inserting (K) then
                  Last_Key := K;
                  Execute_Command ("self_insert");
               else
                  Message (To_String (Seq) & " is undefined");
               end if;
               return;
         end case;
      end loop;
   end Dispatch;

   -------------------------------------------------------------------------
   --  Commands that need the dispatcher or keymaps
   -------------------------------------------------------------------------

   procedure Execute_Extended_Command is
      Given : constant Boolean := Arg_Given;
      Arg   : constant Positive := Prefix_Arg;
      Input : Unbounded_String;
      Ok    : Boolean;
   begin
      Read_String ((if Given then Img (Arg) & " M-x " else "M-x "), "", Input, Ok,
                   Commands.Complete'Access);
      if not Ok or else Length (Input) = 0 then
         return;
      end if;
      declare
         Name : constant String := Normalize (To_String (Input));
      begin
         if not Exists (Name) then
            Message ("No such command: " & Name);
            return;
         elsif Name = "execute_extended_command" then
            return;
         end if;
         Prefix_Arg := Arg;
         Arg_Given := Given;
         Execute_Command (Name);
         if Current_Message = "" and then not Quit_Requested then
            declare
               Where : constant String := Where_Is (Global_Map, Name);
            begin
               if Where /= "" then
                  Message ("You can run the command " & Name & " with " & Where);
               end if;
            end;
         end if;
      end;
   end Execute_Extended_Command;

   procedure Describe_Key is
      Map    : Keymap_Access := Global_Map;
      Mode_M : Keymap_Access := Mode_Map (Windows.Current_Buffer.Mode);
      Seq    : Unbounded_String;
      Bnd    : Binding;
      K      : Key := Read_Key_Echo ("Describe key: ");
   begin
      loop
         K := Meta_Of_Esc (K, "Describe key: " & To_String (Seq));
         Bnd := Lookup_Key (Mode_M, Map, K);
         if Length (Seq) > 0 then
            Append (Seq, " ");
         end if;
         Append (Seq, Describe (K));
         case Bnd.Kind is
            when Prefix =>
               K := Read_Key_Echo ("Describe key: " & To_String (Seq) & "-");
            when Command =>
               Message (To_String (Seq) & " runs the command " & To_String (Bnd.Name));
               return;
            when Unbound =>
               if Map = Global_Map and then Is_Self_Inserting (K) then
                  Message (To_String (Seq) & " runs the command self_insert");
               else
                  Message (To_String (Seq) & " is undefined");
               end if;
               return;
         end case;
      end loop;
   end Describe_Key;

   procedure Describe_Bindings is
      Text : Unbounded_String :=
        To_Unbounded_String (Pad ("Key", 24) & "Command" & L1.LF
                             & Pad ("---", 24) & "-------" & L1.LF);

      procedure Add (Sequence, Name : String) is
      begin
         Append (Text, Pad (Sequence, 23) & " " & Name & L1.LF);
      end Add;
   begin
      For_Each_Binding (Global_Map, Add'Access);
      File_Commands.Show_Special ("*Help*", Text);
   end Describe_Bindings;

   procedure Suspend_Editor is
   begin
      Terminal.Suspend;
      Display.Update_Size;
   end Suspend_Editor;

   procedure Universal_Argument is
   begin
      null;  --  Handled by Dispatch; registered so it can be bound
   end Universal_Argument;

   -------------------------------------------------------------------------
   --  Keyboard macros
   -------------------------------------------------------------------------

   procedure Start_Kbd_Macro is
   begin
      if Keys.Recording then
         Message ("Already defining a keyboard macro");
      elsif Executing_Macro then
         Message ("Cannot define a keyboard macro while one is running");
      else
         Keys.Start_Recording;
         Message ("Defining keyboard macro...");
      end if;
   end Start_Kbd_Macro;

   procedure End_Kbd_Macro is
   begin
      if not Keys.Recording then
         Message ("Not defining a keyboard macro");
         return;
      end if;
      Keys.Stop_Recording (Keep => Command_Start);
      Message (if Keys.Have_Macro then "Keyboard macro defined"
               else "The keyboard macro is empty");
   end End_Kbd_Macro;

   procedure Play_Macro_Once is
      K : Key;
   begin
      Keys.Play_Macro;
      while Keys.Playing and then not Quit_Requested loop
         K := Read_Key;
         if K.Code /= Key_Resize and then K.Code /= Key_None then
            Clear_Message;
            This_Class := Class_Other;
            This_Command := Null_Unbounded_String;
            Dispatch (K);
            Last_Class := This_Class;
            Last_Command := This_Command;
         end if;
      end loop;
   end Play_Macro_Once;

   --  Run the last macro (C-u N: N times); afterwards "e" runs it again.
   --  An error stops the macro.
   procedure Call_Last_Kbd_Macro is
      Times : constant Positive := Prefix_Arg;
      K     : Key;
   begin
      if Keys.Recording then
         Message ("Cannot run the keyboard macro while defining it");
         return;
      elsif Executing_Macro then
         Message ("A keyboard macro cannot run itself");
         return;
      elsif not Keys.Have_Macro then
         Message ("No keyboard macro is defined");
         return;
      end if;
      Executing_Macro := True;
      begin
         loop
            for I in 1 .. Times loop
               Play_Macro_Once;
               exit when Quit_Requested;
            end loop;
            exit when Batch_Mode or else Quit_Requested;
            K := Read_Key_Echo ("Press e to run the keyboard macro again");
            exit when K.Code /= Character'Pos ('e') or else K.Meta;
         end loop;
      exception
         when others =>
            Keys.Cancel_Playback;
            Executing_Macro := False;
            raise;
      end;
      Executing_Macro := False;
      if not Batch_Mode and then not Quit_Requested then
         Keys.Unread (K);
      end if;
   end Call_Last_Kbd_Macro;

   -------------------------------------------------------------------------
   --  Help about commands
   -------------------------------------------------------------------------

   procedure Describe_Function is
      Input : Unbounded_String;
      Ok    : Boolean;
   begin
      Read_String ("Describe command: ", "", Input, Ok, Commands.Complete'Access);
      if not Ok or else Length (Input) = 0 then
         return;
      end if;
      declare
         Name  : constant String := Normalize (To_String (Input));
         Where : constant String := Where_Is (Global_Map, Name);
      begin
         if not Exists (Name) then
            Message ("No such command: " & Name);
         elsif Where = "" then
            Message (Name & " is not bound to a key; run it with M-x " & Name);
         else
            Message (Name & " is bound to " & Where);
         end if;
      end;
   end Describe_Function;

   --  List the commands whose names contain a text, with their keys
   procedure Apropos_Command is
      package Sorting is new String_Vectors.Generic_Sorting;
      Input : Unbounded_String;
      Ok    : Boolean;
   begin
      Read_String ("Apropos command (part of the name): ", "", Input, Ok);
      if not Ok then
         return;
      end if;
      declare
         Pattern : constant String := Normalize (To_String (Input));
         Names   : String_Vectors.Vector := Commands.Complete ("");
         Text    : Unbounded_String;
      begin
         Sorting.Sort (Names);
         for Name of Names loop
            if Pattern = "" or else Ada.Strings.Fixed.Index (Name, Pattern) > 0 then
               Append (Text, Pad (Name, 31) & " " & Where_Is (Global_Map, Name) & L1.LF);
            end if;
         end loop;
         if Length (Text) = 0 then
            Message ("No command name contains " & Pattern);
         else
            File_Commands.Show_Special ("*Help*", Text);
         end if;
      end;
   end Apropos_Command;

   -------------------------------------------------------------------------
   --  Default bindings
   -------------------------------------------------------------------------

   procedure Default_Bindings is
      procedure B (Sequence, Name : String) is
      begin
         Bind (Global_Map, Sequence, Name);
      end B;
   begin
      --  Motion
      B ("C-f", "forward_char");            B ("<right>", "forward_char");
      B ("C-b", "backward_char");           B ("<left>", "backward_char");
      B ("C-n", "next_line");               B ("<down>", "next_line");
      B ("C-p", "previous_line");           B ("<up>", "previous_line");
      B ("M-f", "forward_word");            B ("C-<right>", "forward_word");
      B ("M-b", "backward_word");           B ("C-<left>", "backward_word");
      B ("C-a", "beginning_of_line");       B ("<home>", "beginning_of_line");
      B ("C-e", "end_of_line");             B ("<end>", "end_of_line");
      B ("M-<", "beginning_of_buffer");
      B ("M->", "end_of_buffer");
      B ("C-v", "scroll_up");               B ("<next>", "scroll_up");
      B ("M-v", "scroll_down");             B ("<prior>", "scroll_down");
      B ("C-l", "recenter");
      B ("M-g g", "goto_line");             B ("M-g M-g", "goto_line");

      --  Editing
      B ("RET", "newline");
      B ("C-j", "newline_and_indent");
      B ("C-o", "open_line");
      B ("TAB", "insert_tab");
      B ("C-d", "delete_char");             B ("<delete>", "delete_char");
      B ("DEL", "delete_backward_char");    B ("C-h", "delete_backward_char");
      B ("C-q", "quoted_insert");
      B ("C-t", "transpose_chars");
      B ("M-u", "upcase_word");
      B ("M-l", "downcase_word");
      B ("M-c", "capitalize_word");

      --  Mark, kill, yank, undo
      B ("C-SPC", "set_mark");
      B ("C-x C-x", "exchange_point_and_mark");
      B ("C-x h", "mark_whole_buffer");
      B ("C-k", "kill_line");
      B ("C-w", "kill_region");
      B ("M-w", "copy_region");
      B ("M-d", "kill_word");
      B ("M-DEL", "backward_kill_word");
      B ("C-y", "yank");
      B ("M-y", "yank_pop");
      B ("C-_", "undo");                    B ("C-x u", "undo");

      --  Search
      B ("C-s", "isearch_forward");
      B ("C-r", "isearch_backward");
      B ("M-%", "query_replace");
      B ("C-M-s", "isearch_forward_regexp");
      B ("C-M-r", "isearch_backward_regexp");

      --  Comments, brackets, filling
      B ("M-;", "comment_dwim");
      B ("C-M-f", "forward_sexp");
      B ("C-M-b", "backward_sexp");
      B ("M-q", "fill_paragraph");
      B ("C-x f", "set_fill_column");

      --  Shell
      B ("M-!", "shell_command");
      B ("M-|", "shell_command_on_region");

      --  Files and buffers
      B ("C-x C-f", "find_file");
      B ("C-x C-s", "save_buffer");
      B ("C-x C-w", "write_file");
      B ("C-x s", "save_some_buffers");
      B ("C-x i", "insert_file");
      B ("C-x C-q", "toggle_read_only");
      B ("C-x b", "switch_to_buffer");
      B ("C-x C-b", "list_buffers");
      B ("C-x k", "kill_buffer");
      B ("C-x C-c", "save_buffers_kill_editor");

      --  Windows
      B ("C-x 2", "split_window");
      B ("C-x o", "other_window");
      B ("C-x 0", "delete_window");
      B ("C-x 1", "delete_other_windows");

      --  Misc
      B ("C-x =", "what_cursor_position");
      B ("M-=", "count_words_region");

      --  Keyboard macros
      B ("C-x (", "start_kbd_macro");
      B ("C-x )", "end_kbd_macro");
      B ("C-x e", "call_last_kbd_macro");

      --  Whitespace, words, lines and paragraphs
      B ("M-m", "back_to_indentation");
      B ("M-\", "delete_horizontal_space");
      B ("M-SPC", "just_one_space");
      B ("M-^", "delete_indentation");
      B ("M-z", "zap_to_char");
      B ("M-t", "transpose_words");
      B ("C-x C-t", "transpose_lines");
      B ("C-x C-u", "upcase_region");
      B ("C-x C-l", "downcase_region");
      B ("M-{", "backward_paragraph");
      B ("M-}", "forward_paragraph");
      B ("M-/", "dabbrev_expand");
      B ("C-g", "keyboard_quit");
      B ("C-M-g", "keyboard_quit");
      B ("C-u", "universal_argument");
      B ("M-x", "execute_extended_command");
      B ("C-z", "suspend_editor");
      B ("M-:", "eval_expression");

      --  Compiling
      B ("C-x `", "next_error");
      B ("M-g n", "next_error");            B ("M-g M-n", "next_error");
      B ("M-g p", "previous_error");        B ("M-g M-p", "previous_error");
   end Default_Bindings;

   -------------------------------------------------------------------------
   --  The startup screen
   -------------------------------------------------------------------------

   About_Rows : constant := 9;  --  Lines in About_Text

   function About_Text return String is
     (Version_Info.Name & " " & Version_Info.Number & " - " & Version_Info.Title & L1.LF
      & Version_Info.Description & L1.LF
      & "Copyright (C) " & Version_Info.Year & " " & Version_Info.Author & ".  MIT license." & L1.LF
      & Version_Info.Homepage & L1.LF
      & L1.LF
      & "C-x C-f  open a file      C-x C-s  save        C-x C-c  exit" & L1.LF
      & "M-x      run a command    C-g      cancel      C-x 1    close this window" & L1.LF
      & "M-x describe_bindings lists all keys.  To not show this window at startup," & L1.LF
      & "put  Set_Startup_Screen (False);  in ~/.avoerc");

   function About_Buffer return Buffer_Access is
      B : Buffer_Access := Buffer_List.Find ("*About*");
   begin
      if B = null then
         B := Buffer_List.Create ("*About*");
      end if;
      B.Read_Only := False;
      B.Undo_Enabled := False;
      Erase (B.all);
      Insert (B.all, About_Text);
      B.Point := 0;
      B.Modified := False;
      B.Read_Only := True;
      B.Line_Numbers := False;
      return B;
   end About_Buffer;

   --  As in Jove: the upper window shows *About*, the lower one the file,
   --  with the cursor.  Skipped when the screen is too small for both.
   procedure Show_Startup_Screen is
      Ok : Boolean;
   begin
      if Windows.Count /= 1 or else Windows.Current.Height < About_Rows + 6 then
         return;
      end if;
      declare
         Total : constant Positive := Windows.Current.Height + 1;  --  With the mode line
      begin
         Windows.Split_Current (Ok);
         if not Ok then
            return;
         end if;
         Windows.Show_Buffer (Windows.Get (1), About_Buffer);
         Windows.Get (1).Height := About_Rows;
         Windows.Get (2).Height := Total - About_Rows - 2;
         Windows.Select_Window (2);
      end;
   end Show_Startup_Screen;

   procedure About_Avoe is
   begin
      File_Commands.Show_Special ("*About*", To_Unbounded_String (About_Text));
   end About_Avoe;

   procedure Register_Editor_Commands is
   begin
      Register ("about_avoe", About_Avoe'Access);
      Register ("execute_extended_command", Execute_Extended_Command'Access);
      Register ("describe_key", Describe_Key'Access);
      Register ("describe_bindings", Describe_Bindings'Access);
      Register ("suspend_editor", Suspend_Editor'Access);
      Register ("universal_argument", Universal_Argument'Access);
      Register ("start_kbd_macro", Start_Kbd_Macro'Access);
      Register ("end_kbd_macro", End_Kbd_Macro'Access);
      Register ("call_last_kbd_macro", Call_Last_Kbd_Macro'Access);
      Register ("describe_function", Describe_Function'Access);
      Register ("apropos_command", Apropos_Command'Access);
   end Register_Editor_Commands;

   -------------------------------------------------------------------------
   --  Command loop
   -------------------------------------------------------------------------

   procedure Setup (Files : String_Vectors.Vector; Load_Init : Boolean) is
      Scratch : constant Buffer_Access := Buffer_List.Create ("*scratch*");
      First   : Buffer_Access := null;
   begin
      Edit_Commands.Register_All;
      File_Commands.Register_All;
      Search_Commands.Register_All;
      Script_Commands.Register_All;
      Modes.Register_All;
      Compile_Commands.Register_All;
      Shell_Commands.Register_All;
      Register_Editor_Commands;
      Default_Bindings;

      Windows.Initialize (Scratch, 23);
      if not Batch_Mode then
         Display.Update_Size;
      end if;

      Script_Commands.Load_Startup_Files (User_Files => Load_Init);

      for F of Files loop
         declare
            B : constant Buffer_Access := File_Commands.Visit_File (F);
         begin
            if First = null then
               First := B;
            end if;
         end;
      end loop;
      if First /= null then
         File_Commands.Switch_To (First);
      end if;
   end Setup;

   --  React when another program changed the current buffer's file: an
   --  unmodified buffer is reloaded, a modified one gets a warning (once).
   procedure Check_External_Change is
      B : constant Buffer_Access := Windows.Current_Buffer;
   begin
      if not Changed_On_Disk (B.all) then
         return;
      elsif not B.Modified then
         declare
            Msg : Unbounded_String;
            Ok  : Boolean;
         begin
            Revert (B.all, Msg, Ok);
            if Ok then
               Auto_Save.Remove (B.all);
               Message ("Reverted " & To_String (B.Name) & ": the file changed on disk");
            end if;
         end;
      else
         declare
            Now : constant Long_Long_Integer := File_IO.Info (To_String (B.File_Name)).Mtime;
         begin
            if Now /= B.Warned_Mtime then
               B.Warned_Mtime := Now;
               Message (To_String (B.Name) & " changed on disk; saving will ask first, "
                        & "M-x revert_buffer reloads it");
            end if;
         end;
      end if;
   end Check_External_Change;

   function Run_Batch (Script : String; Files : String_Vectors.Vector) return Boolean is
   begin
      Batch_Mode := True;
      Setup (Files, Load_Init => False);
      return Script_Commands.Run_Batch (Script);
   end Run_Batch;

   --  Append the details of an internal error, with a traceback, to
   --  internal-errors.log in the state directory; return its name for the
   --  message, or "" if it could not be written.
   function Log_Internal_Error (E : Ada.Exceptions.Exception_Occurrence) return String is
      use Ada.Text_IO;
      Dir  : constant String := Paths.State_Directory;
      Name : constant String := Dir & "/internal-errors.log";
      F    : File_Type;
   begin
      Ada.Directories.Create_Path (Dir);
      if Ada.Directories.Exists (Name) then
         Open (F, Append_File, Name);
      else
         Create (F, Out_File, Name);
      end if;
      Put_Line (F, Ada.Calendar.Formatting.Image (Ada.Calendar.Clock)
                & " avoe internal error in " & To_String (This_Command));
      Put (F, Ada.Exceptions.Exception_Information (E));
      New_Line (F);
      Close (F);
      return File_Names.Abbreviate (Name);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         return "";
   end Log_Internal_Error;

   procedure Run
     (Files     : String_Vectors.Vector;
      Load_Init : Boolean := True;
      Splash    : Boolean := True)
   is
      K : Key;
   begin
      Setup (Files, Load_Init);
      if Splash and then Commands.Startup_Screen then
         Show_Startup_Screen;
      end if;

      while not Quit_Requested loop
         if not Terminal.Input_Pending and then not Keys.Key_Pending then
            Redisplay;
         end if;

         --  Wait for a key.  Meanwhile show compiler output, and auto-save
         --  once there has been no input for a while.
         declare
            Idle : Natural := 0;
         begin
            while not Terminal.Input_Pending and then not Keys.Key_Pending loop
               declare
                  Keyboard : Boolean;
                  Output   : Boolean;
                  pragma Warnings (Off, Output);
               begin
                  if Compile_Commands.Running then
                     Compile_Commands.Collect_Output (Keyboard);
                     Redisplay;
                  else
                     Processes.Wait_Input ((Pid => -1, Fd => -1), 1000, Keyboard, Output);
                  end if;
                  exit when Keyboard;
                  Idle := Idle + 1;
                  if Idle = Auto_Save.Idle_Seconds then
                     Auto_Save.Save_All;
                  end if;
               end;
            end loop;
         end;

         K := Read_Key;
         if K.Code = Key_Resize then
            Display.Update_Size;
         elsif K.Code /= Key_None then
            Clear_Message;
            This_Class := Class_Other;
            This_Command := Null_Unbounded_String;
            --  K is the last key recorded (also when it was read before
            --  and given back with Unread)
            Command_Start :=
              (if Keys.Recording and then Keys.Recorded_Count > 0
               then Keys.Recorded_Count - 1 else 0);
            begin
               Dispatch (K);
            exception
               when Terminal.Input_Closed =>
                  raise;
               when E : Scripts.Script_Error =>
                  Display.Clear_Highlight;
                  Message (Ada.Exceptions.Exception_Message (E));
               when Read_Only_Error =>
                  Display.Clear_Highlight;
                  Message ("Buffer is read-only: " & To_String (Windows.Current_Buffer.Name));
               when E : others =>
                  Display.Clear_Highlight;
                  declare
                     Log : constant String := Log_Internal_Error (E);
                  begin
                     Message ("Internal error: " & Ada.Exceptions.Exception_Name (E) & " "
                              & Ada.Exceptions.Exception_Message (E)
                              & (if Log = "" then "" else " (details in " & Log & ")"));
                  end;
            end;
            Last_Class := This_Class;
            Last_Command := This_Command;
            Auto_Save.Note_Keystroke;
            Check_External_Change;
         end if;
      end loop;
      Compile_Commands.Shutdown;
      Auto_Save.Remove_All;
   end Run;

end Editor;
