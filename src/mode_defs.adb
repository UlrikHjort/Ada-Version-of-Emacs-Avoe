-- ***************************************************************************
--                              Avoe - Mode_Defs
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

with Ada.Containers.Vectors;
with File_Names;
with Utils;

package body Mode_Defs is

   package Def_Vectors is new Ada.Containers.Vectors (Positive, Mode_Def);

   Table : Def_Vectors.Vector;

   function "+" (S : String) return Unbounded_String renames To_Unbounded_String;

   function Lower (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         C := Utils.To_Lower (C);
      end loop;
      return R;
   end Lower;

   function Normalize_Name (Name : String) return String is
      R : String := Lower (Name);
   begin
      for C of R loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      return R;
   end Normalize_Name;

   --  Blank separated words as " w1 w2 " (tabs and newlines count as blanks)
   function Normalize_Words (Words : String; To_Lower : Boolean) return String is
      Source  : constant String := (if To_Lower then Lower (Words) else Words);
      Result  : Unbounded_String := +" ";
      In_Word : Boolean := False;
   begin
      for C of Source loop
         if C = ' ' or else Character'Pos (C) < 32 then
            if In_Word then
               Append (Result, ' ');
               In_Word := False;
            end if;
         else
            Append (Result, C);
            In_Word := True;
         end if;
      end loop;
      if In_Word then
         Append (Result, ' ');
      end if;
      return To_String (Result);
   end Normalize_Words;

   function Count return Natural is (Natural (Table.Length));

   function Get (Mode : Mode_Kind) return Mode_Def is
     (if Mode <= Count then Table (Mode) else Table (Fundamental_Mode));

   function Find (Name : String) return Natural is
      N : constant String := Normalize_Name (Name);
   begin
      for I in 1 .. Count loop
         if To_String (Table (I).Name) = N then
            return I;
         end if;
      end loop;
      --  The script mode is also known by its title, Avoe-Script
      return (if N = "avoe_script" then Script_Mode else 0);
   end Find;

   function Define (Def : Mode_Def) return Mode_Kind is
      D : Mode_Def := Def;
      I : constant Natural := Find (To_String (Def.Name));
   begin
      D.Name := +Normalize_Name (To_String (Def.Name));
      if Length (D.Title) = 0 then
         D.Title := D.Name;
      end if;
      D.Extensions := +Normalize_Words (To_String (Def.Extensions), True);
      D.Keywords := +Normalize_Words (To_String (Def.Keywords), not Def.Case_Sensitive);
      D.Types := +Normalize_Words (To_String (Def.Types), not Def.Case_Sensitive);
      --  Defining a mode again replaces it and keeps its number
      if I > 0 then
         Table.Replace_Element (I, D);
         return I;
      end if;
      Table.Append (D);
      return Table.Last_Index;
   end Define;

   function For_File (File_Name : String) return Mode_Kind is
      N : constant String := Lower (File_Names.Simple_Name (File_Name));
   begin
      --  The newest mode first, so a user's mode wins over a bundled one.
      --  A word starting with "." matches the end of the name (.c, .bashrc),
      --  any other word the whole name (Makefile).
      for I in reverse 1 .. Count loop
         declare
            Words : constant String := To_String (Table (I).Extensions);
            Start : Positive := Words'First;
         begin
            for J in Words'Range loop
               if Words (J) = ' ' then
                  if J > Start then
                     declare
                        W : constant String := Words (Start .. J - 1);
                     begin
                        if N = W
                          or else (W (W'First) = '.' and then N'Length > W'Length
                                   and then N (N'Last - W'Length + 1 .. N'Last) = W)
                        then
                           return I;
                        end if;
                     end;
                  end if;
                  Start := J + 1;
               end if;
            end loop;
         end;
      end loop;
      return Fundamental_Mode;
   end For_File;

   function Name (Mode : Mode_Kind) return String is (To_String (Get (Mode).Name));
   function Title (Mode : Mode_Kind) return String is (To_String (Get (Mode).Title));

   function Names return String_Vectors.Vector is
      Result : String_Vectors.Vector;
   begin
      for D of Table loop
         Result.Append (To_String (D.Name));
      end loop;
      return Result;
   end Names;

   procedure Set_Formatter (Mode : Mode_Kind; Command : String) is
      D : Mode_Def := Get (Mode);
   begin
      if Mode <= Count then
         D.Formatter := +Command;
         Table.Replace_Element (Mode, D);
      end if;
   end Set_Formatter;

   Id : Mode_Kind;

begin
   --  The built-in modes, numbered as the constants in Buffers
   Id := Define ((Name => +"fundamental", Title => +"Fundamental", others => <>));
   pragma Assert (Id = Fundamental_Mode);
   Id := Define ((Name => +"ada", Title => +"Ada", Extensions => +".adb .ads .ada .gpr",
                  Highlighter => Ada_Highlighting, Line_Comment => +"--",
                  Formatter => +"gnatpp --pipe %f", others => <>));
   pragma Assert (Id = Ada_Mode);
   Id := Define ((Name => +"script", Title => +"Avoe-Script", Extensions => +".avoe .avoerc",
                  Highlighter => Ada_Highlighting, Line_Comment => +"--", others => <>));
   pragma Assert (Id = Script_Mode);
   Id := Define ((Name => +"compilation", Title => +"Compilation",
                  Highlighter => Compilation_Highlighting, others => <>));
   pragma Assert (Id = Compilation_Mode);
end Mode_Defs;
