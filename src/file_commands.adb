-- ***************************************************************************
--                            Avoe - File_Commands
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

with Auto_Save;
with Buffer_List;
with Commands;   use Commands;
with File_Names;
with Modes;
with Minibuffer; use Minibuffer;
with Utils;      use Utils;
with Windows;

package body File_Commands is

   package L1 renames Ada.Characters.Latin_1;

   function Cur return Buffer_Access renames Windows.Current_Buffer;

   function File_Completer return Completer is (File_Names.Complete'Access);
   function Buffer_Completer return Completer is (Buffer_List.Complete_Name'Access);

   function Default_Directory return String is
     (File_Names.Directory_Of (To_String (Cur.File_Name)));

   procedure Switch_To (B : Buffer_Access) is
   begin
      Windows.Show_Buffer (Windows.Current, B);
      Buffer_List.Touch (B);
   end Switch_To;

   function Visit_File (Name : String) return Buffer_Access is
      Full : constant String := File_Names.Absolute (Name);
      B    : Buffer_Access;
      Msg  : Unbounded_String;
      Ok   : Boolean;
   begin
      if File_Names.Is_Directory (Full) then
         Message (File_Names.Abbreviate (Full) & " is a directory");
         return null;
      end if;
      B := Buffer_List.Find_File (Full);
      if B /= null then
         return B;
      end if;
      B := Buffer_List.Create (File_Names.Simple_Name (Full));
      Load (B.all, Full, Msg, Ok);
      if Length (Msg) > 0 then
         Message (To_String (Msg));
      end if;
      if not Ok then
         Buffer_List.Remove (B);
         return null;
      end if;
      Modes.Set_Mode (B, Modes.Mode_For_File (Full));

      if not Batch_Mode and then Auto_Save.Recovery_Available (Full)
        and then Ask ("Auto-saved changes to " & File_Names.Simple_Name (Full)
                      & " are newer than the file; recover them?") = Yes
      then
         Auto_Save.Recover (B.all, Ok);
         Message (if Ok then "Recovered auto-saved changes: C-x C-s saves them, "
                             & "M-x revert_buffer discards them"
                  else "Could not read the auto-save file");
      end if;
      return B;
   end Visit_File;

   procedure Show_Special (Name : String; Content : Unbounded_String) is
      B : Buffer_Access := Buffer_List.Find (Name);
   begin
      if B = null then
         B := Buffer_List.Create (Name);
      end if;
      B.Read_Only := False;
      B.Undo_Enabled := False;
      Erase (B.all);
      Insert (B.all, Content);
      B.Point := 0;
      B.Modified := False;
      B.Read_Only := True;
      Windows.Pop_To_Buffer (B);
   end Show_Special;

   procedure Save_One (B : Buffer_Access) is
      Msg : Unbounded_String;
      Ok  : Boolean;
   begin
      if Changed_On_Disk (B.all) and then not Batch_Mode
        and then Ask (File_Names.Abbreviate (To_String (B.File_Name))
                      & " changed on disk since it was read; save anyway?") /= Yes
      then
         Message ("Not saved");
         return;
      end if;
      Save (B.all, Msg, Ok);
      Message (To_String (Msg));
      if Ok then
         Auto_Save.Remove (B.all);
         B.Warned_Mtime := -1;
      end if;
   end Save_One;

   -------------------------------------------------------------------------
   --  Files
   -------------------------------------------------------------------------

   procedure Find_File is
      Name : Unbounded_String;
      Ok   : Boolean;
      B    : Buffer_Access;
   begin
      Read_String ("Find file: ", Default_Directory, Name, Ok, File_Completer);
      if not Ok or else Length (Name) = 0 then
         return;
      end if;
      B := Visit_File (To_String (Name));
      if B /= null then
         Switch_To (B);
      end if;
   end Find_File;

   procedure Write_File is
      Name : Unbounded_String;
      Ok   : Boolean;
      B    : constant Buffer_Access := Cur;
   begin
      Read_String ("Write file: ", Default_Directory, Name, Ok, File_Completer);
      if not Ok or else Length (Name) = 0 then
         return;
      end if;
      declare
         Full : constant String := File_Names.Absolute (To_String (Name));
      begin
         if File_Names.Is_Directory (Full) then
            Message (File_Names.Abbreviate (Full) & " is a directory");
            return;
         end if;
         if Full /= To_String (B.File_Name)
           and then File_Names.Exists (Full)
           and then Ask ("File " & File_Names.Abbreviate (Full)
                         & " exists; overwrite?") /= Yes
         then
            return;
         end if;
         B.File_Name := To_Unbounded_String (Full);
         B.Name := To_Unbounded_String
           (Buffer_List.Unique_Name (File_Names.Simple_Name (Full), Except => B));
         B.Read_Only := False;
         if B.Mode = Fundamental_Mode then
            Modes.Set_Mode (B, Modes.Mode_For_File (Full));
         end if;
         Save_One (B);
      end;
   end Write_File;

   procedure Save_Buffer is
   begin
      if Length (Cur.File_Name) = 0 then
         Write_File;
      elsif not Cur.Modified then
         Message ("(No changes need to be saved)");
      else
         Save_One (Cur);
      end if;
   end Save_Buffer;

   --  Offer to save each modified file buffer.  False if cancelled or a
   --  save failed.
   function Offer_Saves (Saved_Any : out Boolean) return Boolean is
   begin
      Saved_Any := False;
      for I in 1 .. Buffer_List.Count loop
         declare
            B : constant Buffer_Access := Buffer_List.Get (I);
         begin
            if B.Modified and then Length (B.File_Name) > 0 then
               case Ask ("Save file "
                         & File_Names.Abbreviate (To_String (B.File_Name)) & "?")
               is
                  when Yes =>
                     Save_One (B);
                     if B.Modified then
                        return False;
                     end if;
                     Saved_Any := True;
                  when No =>
                     null;
                  when Cancel =>
                     return False;
               end case;
            end if;
         end;
      end loop;
      return True;
   end Offer_Saves;

   procedure Save_Some_Buffers is
      Saved_Any : Boolean;
   begin
      if Offer_Saves (Saved_Any) and then not Saved_Any then
         Message ("(No files need saving)");
      end if;
   end Save_Some_Buffers;

   procedure Save_Buffers_Kill_Editor is
      Saved_Any : Boolean;
   begin
      if not Offer_Saves (Saved_Any) then
         return;
      end if;
      for I in 1 .. Buffer_List.Count loop
         declare
            B : constant Buffer_Access := Buffer_List.Get (I);
         begin
            if Confirm_Exit then
               --  Any unsaved buffer counts, also one without a file such
               --  as *scratch*; the answer must be typed out
               if B.Modified and then not B.Read_Only then
                  if Ask_Yes_Or_No ("Some buffers haven't been saved; leave anyway?") /= Yes then
                     return;
                  end if;
                  exit;
               end if;
            elsif B.Modified and then Length (B.File_Name) > 0 then
               if Ask ("Modified buffers exist; exit anyway?") /= Yes then
                  return;
               end if;
               exit;
            end if;
         end;
      end loop;
      Quit_Requested := True;
   end Save_Buffers_Kill_Editor;

   procedure Insert_File is
      Name : Unbounded_String;
      Ok   : Boolean;
   begin
      Read_String ("Insert file: ", Default_Directory, Name, Ok, File_Completer);
      if not Ok or else Length (Name) = 0 then
         return;
      end if;
      declare
         Full : constant String := File_Names.Absolute (To_String (Name));
         Temp : Buffer;
         Msg  : Unbounded_String;
         B    : Buffer renames Cur.all;
      begin
         if not File_Names.Exists (Full) then
            Message ("No such file: " & File_Names.Abbreviate (Full));
            return;
         end if;
         Load (Temp, Full, Msg, Ok);
         if not Ok then
            Message (To_String (Msg));
            return;
         end if;
         declare
            Start : constant Natural := B.Point;
         begin
            Insert (B, Text_Of (Temp, 0, Length (Temp)));
            B.Mark := B.Point;
            B.Mark_Set := True;
            B.Point := Start;
         end;
      end;
   end Insert_File;

   procedure Revert_Buffer is
      B   : constant Buffer_Access := Cur;
      Msg : Unbounded_String;
      Ok  : Boolean;
   begin
      if Length (B.File_Name) = 0 then
         Message ("The buffer is not visiting a file");
         return;
      elsif B.Modified
        and then Ask ("Discard changes and reload "
                      & File_Names.Abbreviate (To_String (B.File_Name)) & "?") /= Yes
      then
         return;
      end if;
      Revert (B.all, Msg, Ok);
      Message (To_String (Msg));
      if Ok then
         Auto_Save.Remove (B.all);
      end if;
   end Revert_Buffer;

   procedure Recover_File is
      B  : constant Buffer_Access := Cur;
      Ok : Boolean;
   begin
      if Length (B.File_Name) = 0
        or else not File_Names.Exists (Auto_Save.File_For (To_String (B.File_Name)))
      then
         Message ("No auto-saved changes for this buffer");
         return;
      end if;
      Auto_Save.Recover (B.all, Ok);
      Message (if Ok then "Recovered auto-saved changes" else "Could not read the auto-save file");
   end Recover_File;

   --  Switch between a body and its spec (foo.adb / foo.ads, foo.c / foo.h)
   procedure Find_Other_File is
      Name : constant String := To_String (Cur.File_Name);

      function Try (From, To : String) return Boolean is
         B : Buffer_Access;
      begin
         if Name'Length <= From'Length
           or else Name (Name'Last - From'Length + 1 .. Name'Last) /= From
         then
            return False;
         end if;
         B := Visit_File (Name (Name'First .. Name'Last - From'Length) & To);
         if B /= null then
            Switch_To (B);
         end if;
         return True;
      end Try;
   begin
      if Name = "" then
         Message ("The buffer is not visiting a file");
      elsif not (Try (".adb", ".ads") or else Try (".ads", ".adb")
                 or else Try (".c", ".h") or else Try (".h", ".c")
                 or else Try (".cpp", ".hpp") or else Try (".hpp", ".cpp")
                 or else Try (".cc", ".hh") or else Try (".hh", ".cc"))
      then
         Message ("No other file is known for " & File_Names.Simple_Name (Name));
      end if;
   end Find_Other_File;

   procedure Toggle_Read_Only is
   begin
      Cur.Read_Only := not Cur.Read_Only;
      Message (if Cur.Read_Only then "Read-only mode enabled"
               else "Read-only mode disabled");
   end Toggle_Read_Only;

   -------------------------------------------------------------------------
   --  Buffers
   -------------------------------------------------------------------------

   procedure Switch_To_Buffer is
      Other   : constant Buffer_Access := Buffer_List.Other_Buffer (Cur);
      Default : constant String :=
        (if Other = null then "" else To_String (Other.Name));
      Name    : Unbounded_String;
      Ok      : Boolean;
      B       : Buffer_Access;
   begin
      Read_String
        ((if Default = "" then "Switch to buffer: "
          else "Switch to buffer (default " & Default & "): "),
         "", Name, Ok, Buffer_Completer);
      if not Ok then
         return;
      end if;
      if Length (Name) = 0 then
         Name := To_Unbounded_String (Default);
      end if;
      if Length (Name) = 0 then
         return;
      end if;
      B := Buffer_List.Find (To_String (Name));
      if B = null then
         B := Buffer_List.Create (To_String (Name));
      end if;
      Switch_To (B);
   end Switch_To_Buffer;

   procedure List_Buffers is
      Text : Unbounded_String :=
        To_Unbounded_String
          (" MR " & Pad ("Buffer", 24) & Pad ("Size", 10) & "File" & L1.LF
           & " -- " & Pad ("------", 24) & Pad ("----", 10) & "----" & L1.LF);
   begin
      for I in 1 .. Buffer_List.Count loop
         declare
            B : constant Buffer_Access := Buffer_List.Get (I);
         begin
            Append (Text,
                    " " & (if B = Cur then "." else " ")
                    & (if B.Read_Only then "%" elsif B.Modified then "*" else " ")
                    & " " & Pad (To_String (B.Name), 23) & " "
                    & Pad (Img (Length (B.all)), 9) & " "
                    & File_Names.Abbreviate (To_String (B.File_Name)) & L1.LF);
         end;
      end loop;
      Show_Special ("*Buffer List*", Text);
   end List_Buffers;

   procedure Kill_Buffer is
      Default : constant String := To_String (Cur.Name);
      Name    : Unbounded_String;
      Ok      : Boolean;
      B       : Buffer_Access;
      Other   : Buffer_Access;
   begin
      Read_String ("Kill buffer (default " & Default & "): ", "", Name, Ok,
                   Buffer_Completer);
      if not Ok then
         return;
      end if;
      if Length (Name) = 0 then
         Name := To_Unbounded_String (Default);
      end if;
      B := Buffer_List.Find (To_String (Name));
      if B = null then
         Message ("No such buffer: " & To_String (Name));
         return;
      end if;
      if B.Modified and then Length (B.File_Name) > 0
        and then Ask ("Buffer " & To_String (B.Name) & " modified; kill anyway?") /= Yes
      then
         return;
      end if;

      Auto_Save.Remove (B.all);
      Other := Buffer_List.Other_Buffer (B);
      if Other = null then
         --  The only buffer: turn it into an empty *scratch*
         B.Read_Only := False;
         B.Undo_Enabled := True;
         Erase (B.all);
         B.File_Name := Null_Unbounded_String;
         B.Name := To_Unbounded_String ("*scratch*");
         return;
      end if;
      Windows.Replace_Buffer (B, Other);
      Buffer_List.Remove (B);
   end Kill_Buffer;

   -------------------------------------------------------------------------
   --  Windows
   -------------------------------------------------------------------------

   procedure Split_Window is
      Ok : Boolean;
   begin
      Windows.Split_Current (Ok);
      if not Ok then
         Message ("Window too small to split");
      end if;
   end Split_Window;

   procedure Other_Window is
   begin
      Windows.Other_Window;
      Buffer_List.Touch (Cur);
   end Other_Window;

   procedure Delete_Window is
      Ok : Boolean;
   begin
      Windows.Delete_Current (Ok);
      if not Ok then
         Message ("Attempt to delete the sole window");
      end if;
   end Delete_Window;

   procedure Delete_Other_Windows is
   begin
      Windows.Delete_Others;
   end Delete_Other_Windows;

   -------------------------------------------------------------------------

   procedure Register_All is
   begin
      Register ("find_file", Find_File'Access);
      Register ("save_buffer", Save_Buffer'Access);
      Register ("write_file", Write_File'Access);
      Register ("save_some_buffers", Save_Some_Buffers'Access);
      Register ("save_buffers_kill_editor", Save_Buffers_Kill_Editor'Access);
      Register ("insert_file", Insert_File'Access);
      Register ("toggle_read_only", Toggle_Read_Only'Access);
      Register ("revert_buffer", Revert_Buffer'Access);
      Register ("find_other_file", Find_Other_File'Access);
      Register ("recover_file", Recover_File'Access);

      Register ("switch_to_buffer", Switch_To_Buffer'Access);
      Register ("list_buffers", List_Buffers'Access);
      Register ("kill_buffer", Kill_Buffer'Access);

      Register ("split_window", Split_Window'Access);
      Register ("other_window", Other_Window'Access, Repeatable => True);
      Register ("delete_window", Delete_Window'Access);
      Register ("delete_other_windows", Delete_Other_Windows'Access);
   end Register_All;

end File_Commands;
