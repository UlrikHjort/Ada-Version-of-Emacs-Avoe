-- ***************************************************************************
--                           Avoe - Script_Commands
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

with Paths;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Buffers;    use Buffers;
with Commands;
with File_Names;
with Minibuffer; use Minibuffer;
with Scripts;
with Scripts.Builtins;
with Scripts.Interpreter;
with Terminal;
with Windows;

package body Script_Commands is

   --  The interpreter calls this now and then, so that C-g stops a script
   --  that runs too long
   function Check_Quit return Boolean is
     (not Batch_Mode and then Terminal.Poll_Quit);

   procedure Eval_Expression is
      Text : Unbounded_String;
      Ok   : Boolean;
   begin
      Read_String ("Eval: ", "", Text, Ok);
      if not Ok then
         return;
      end if;
      declare
         Result : constant String := Scripts.Interpreter.Evaluate (To_String (Text));
      begin
         if Result /= "" then
            Message (Result);
         end if;
      end;
   end Eval_Expression;

   procedure Load_File is
      Name : Unbounded_String;
      Ok   : Boolean;
   begin
      Read_String ("Load file: ",
                   File_Names.Directory_Of (To_String (Windows.Current_Buffer.File_Name)),
                   Name, Ok, File_Names.Complete'Access);
      if not Ok or else Length (Name) = 0 then
         return;
      end if;
      declare
         Full : constant String := File_Names.Absolute (To_String (Name));
      begin
         Scripts.Interpreter.Load_File (Full, File_Names.Abbreviate (Full));
         if Current_Message = "" then
            Message ("Loaded " & File_Names.Abbreviate (Full));
         end if;
      end;
   end Load_File;

   procedure Eval_Buffer is
      B : Buffer renames Windows.Current_Buffer.all;
   begin
      Scripts.Interpreter.Execute_Source
        (To_String (Text_Of (B, 0, Length (B))), To_String (B.Name));
      if Current_Message = "" then
         Message ("Evaluated " & To_String (B.Name));
      end if;
   end Eval_Buffer;

   procedure Eval_Region is
      B : Buffer renames Windows.Current_Buffer.all;
   begin
      if not B.Mark_Set then
         Message ("The mark is not set now, so there is no region");
         return;
      end if;
      Scripts.Interpreter.Execute_Source
        (To_String (Text_Of (B, Natural'Min (B.Point, B.Mark), Natural'Max (B.Point, B.Mark))),
         To_String (B.Name));
      if Current_Message = "" then
         Message ("Evaluated region");
      end if;
   end Eval_Region;

   procedure Register_All is
   begin
      Scripts.Builtins.Register_All;
      Scripts.Interpreter.Interrupt_Check := Check_Quit'Access;
      Commands.Run_Script_Command := Scripts.Interpreter.Run_Command'Access;

      Commands.Register ("eval_expression", Eval_Expression'Access);
      Commands.Register ("load_file", Load_File'Access);
      Commands.Register ("eval_buffer", Eval_Buffer'Access);
      Commands.Register ("eval_region", Eval_Region'Access);
   end Register_All;

   --  An error in a startup script is shown, but the editor still starts
   procedure Load_Script (File, What : String) is
   begin
      Scripts.Interpreter.Load_File (File, File_Names.Abbreviate (File));
   exception
      when E : Scripts.Script_Error =>
         Message ("Error in " & What & ": " & Ada.Exceptions.Exception_Message (E));
   end Load_Script;

   --  Later files can redefine what earlier ones define: bundled scripts,
   --  then the site config, the user's scripts and the init file
   procedure Load_Startup_Files (User_Files : Boolean) is
      Site : constant String := Paths.Site_Config_File;
   begin
      for F of Paths.Script_Files (Paths.Data_Directory) loop
         Load_Script (F, "bundled script");
      end loop;
      if Site /= "" then
         Load_Script (Site, "site config");
      end if;
      if User_Files then
         for F of Paths.Script_Files (Paths.User_Scripts_Directory) loop
            Load_Script (F, "user script");
         end loop;
         declare
            Init : constant String := Paths.Init_File;
         begin
            if Init /= "" then
               Load_Script (Init, "init file");
            end if;
         end;
      end if;
   end Load_Startup_Files;

   function Run_Batch (Script_File : String) return Boolean is
   begin
      Scripts.Interpreter.Load_File (Script_File);
      return True;
   exception
      when E : Scripts.Script_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         return False;
   end Run_Batch;

end Script_Commands;
