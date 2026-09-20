-- ***************************************************************************
--                            Avoe - Main program
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

--  Avoe - a small Emacs-like editor for the terminal, written in Ada.

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;      use Ada.Text_IO;
with Editor;
with Paths;
with String_Vectors;
with Terminal;
with Version_Info;

procedure Avoe is
   Splash    : Boolean := True;
   Files     : String_Vectors.Vector;
   Load_Init : Boolean := True;
   Batch     : Unbounded_String;
   I         : Positive := 1;

   procedure Usage is
   begin
      Put_Line ("usage: avoe [-q] [file ...]");
      Put_Line ("       avoe --batch script.avoe [file ...]");
      Put_Line ("");
      Put_Line ("  -q, --no-init     do not load your scripts and init file");
      Put_Line ("  --no-splash       do not show the startup screen");
      Put_Line ("  --batch SCRIPT    run an Avoe script without a terminal");
      Put_Line ("  --paths           show where scripts and configuration are loaded from");
      Put_Line ("  --version         show the version");
   end Usage;
begin
   while I <= Argument_Count loop
      declare
         A : constant String := Argument (I);
      begin
         if A = "--help" or else A = "-h" then
            Usage;
            return;
         elsif A = "--paths" then
            Paths.Print_Report;
            return;
         elsif A = "--version" then
            Put_Line (Version_Info.Name & " " & Version_Info.Number);
            return;
         elsif A = "-q" or else A = "--no-init" then
            Load_Init := False;
         elsif A = "--no-splash" then
            Splash := False;
         elsif A = "--batch" then
            if I = Argument_Count then
               Put_Line (Standard_Error, "avoe: --batch needs a script file");
               Set_Exit_Status (Failure);
               return;
            end if;
            I := I + 1;
            Batch := To_Unbounded_String (Argument (I));
         else
            Files.Append (A);
         end if;
      end;
      I := I + 1;
   end loop;

   if Length (Batch) > 0 then
      if not Editor.Run_Batch (To_String (Batch), Files) then
         Set_Exit_Status (Failure);
      end if;
      return;
   end if;

   Terminal.Initialize;
   Editor.Run (Files, Load_Init, Splash);
   Terminal.Finalize;

exception
   when Terminal.Not_A_Terminal =>
      Put_Line (Standard_Error, "avoe: standard input/output is not a terminal");
      Set_Exit_Status (Failure);
   when Terminal.Input_Closed =>
      Terminal.Finalize;
      Set_Exit_Status (Failure);
   when E : others =>
      Terminal.Finalize;
      Put_Line (Standard_Error,
                "avoe: fatal error: " & Ada.Exceptions.Exception_Information (E));
      Set_Exit_Status (Failure);
end Avoe;
