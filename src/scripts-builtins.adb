-- ***************************************************************************
--                          Avoe - Scripts.Builtins
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
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Ada_Indent;
with Auto_Save;
with Regex_Search;
with Shell_Commands;
with File_Names;
with Mode_Defs;
with Scripts.Interpreter;
with Buffer_List;
with Compile_Commands;
with Modes;
with Syntax;
with Buffers;       use Buffers;
with Commands;
with Display;
with File_Commands;
with Keymaps;
with Minibuffer;
with Utils;
with Windows;

package body Scripts.Builtins is

   package L1 renames Ada.Characters.Latin_1;

   package Info_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Builtin_Info, Ada.Strings.Hash, "=");

   Table : Info_Maps.Map;

   procedure Define (Name, Params : String; Required : Natural; Func : Builtin_Func) is
      Info  : Builtin_Info;
      Start : Positive := Params'First;
   begin
      Info.Func := Func;
      Info.Required := Required;
      if Params /= "" then
         for I in Params'Range loop
            if Params (I) = ',' then
               Info.Params.Append (Params (Start .. I - 1));
               Start := I + 1;
            end if;
         end loop;
         Info.Params.Append (Params (Start .. Params'Last));
      end if;
      Table.Include (Name, Info);
   end Define;

   function Find (Name : String; Info : out Builtin_Info) return Boolean is
      C : constant Info_Maps.Cursor := Table.Find (Name);
   begin
      if Info_Maps.Has_Element (C) then
         Info := Info_Maps.Element (C);
         return True;
      end if;
      return False;
   end Find;

   procedure Run_Editor_Command (Name : String; Count : Positive; Count_Given : Boolean) is
      Saved_Arg   : constant Positive := Commands.Prefix_Arg;
      Saved_Given : constant Boolean := Commands.Arg_Given;
   begin
      Commands.Prefix_Arg := Count;
      Commands.Arg_Given := Count_Given;
      if Commands.Is_Repeatable (Name) then
         --  Like a prefix argument typed by the user: the repeats continue
         --  each other (undo walks further back) and stop at a message
         --  such as "No further undo information".
         declare
            Before : constant String := Minibuffer.Current_Message;
         begin
            for I in 1 .. Count loop
               Commands.Run (Name);
               exit when Minibuffer.Current_Message /= Before or else Commands.Quit_Requested;
               Commands.Last_Class := Commands.This_Class;
            end loop;
         end;
      else
         Commands.Run (Name);
      end if;
      Commands.Prefix_Arg := Saved_Arg;
      Commands.Arg_Given := Saved_Given;
   exception
      when others =>
         Commands.Prefix_Arg := Saved_Arg;
         Commands.Arg_Given := Saved_Given;
         raise;
   end Run_Editor_Command;

   -------------------------------------------------------------------------
   --  Argument helpers
   -------------------------------------------------------------------------

   function Cur return Buffer_Access renames Windows.Current_Buffer;

   procedure Fail (Msg : String) with No_Return;

   procedure Fail (Msg : String) is
   begin
      raise Builtin_Error with Msg;
   end Fail;

   function Given (Args : Arg_Array; I : Positive) return Boolean is
     (I <= Args'Last and then Args (I).Kind /= V_None);

   function Int_Arg (Args : Arg_Array; I : Positive) return Long_Long_Integer is
   begin
      if Args (I).Kind /= V_Integer then
         Fail ("argument " & Utils.Img (I) & " must be Integer, not " & Kind_Name (Args (I)));
      end if;
      return Args (I).Int;
   end Int_Arg;

   function Str_Arg (Args : Arg_Array; I : Positive) return String is
   begin
      case Args (I).Kind is
         when V_String    => return To_String (Args (I).Str);
         when V_Character => return (1 => Args (I).Char);
         when others =>
            Fail ("argument " & Utils.Img (I) & " must be String, not " & Kind_Name (Args (I)));
      end case;
   end Str_Arg;

   function Bool_Arg (Args : Arg_Array; I : Positive) return Boolean is
   begin
      if Args (I).Kind /= V_Boolean then
         Fail ("argument " & Utils.Img (I) & " must be Boolean, not " & Kind_Name (Args (I)));
      end if;
      return Args (I).Bool;
   end Bool_Arg;

   --  Scripts use 1-based positions: 1 .. Length + 1
   function Position (P : Long_Long_Integer) return Natural is
      Len : constant Natural := Length (Cur.all);
   begin
      if P < 1 or else P > Long_Long_Integer (Len) + 1 then
         Fail ("position" & Long_Long_Integer'Image (P) & " is outside 1 .."
               & Natural'Image (Len + 1));
      end if;
      return Natural (P - 1);
   end Position;

   function Pos_Arg (Args : Arg_Array; I : Positive; Default : Natural) return Natural is
     (if Given (Args, I) then Position (Int_Arg (Args, I)) else Default);

   function Script_Pos (P : Natural) return Value is
     (Make_Int (Long_Long_Integer (P) + 1));

   function Region_Needed return Boolean is
   begin
      if not Cur.Mark_Set then
         Fail ("the mark is not set");
      end if;
      return True;
   end Region_Needed;

   -------------------------------------------------------------------------
   --  Positions and text
   -------------------------------------------------------------------------

   function B_Point (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Script_Pos (Cur.Point);
   end B_Point;

   function B_Point_Min (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Int (1);
   end B_Point_Min;

   function B_Point_Max (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Script_Pos (Length (Cur.all));
   end B_Point_Max;

   function B_Buffer_Size (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Int (Long_Long_Integer (Length (Cur.all)));
   end B_Buffer_Size;

   function B_Goto_Char (Args : Arg_Array) return Value is
   begin
      Cur.Point := Position (Int_Arg (Args, 1));
      return None;
   end B_Goto_Char;

   function B_Insert (Args : Arg_Array) return Value is
   begin
      Insert (Cur.all, Str_Arg (Args, 1));
      return None;
   end B_Insert;

   function B_Delete_Region (Args : Arg_Array) return Value is
      A : constant Natural := Position (Int_Arg (Args, 1));
      B : constant Natural := Position (Int_Arg (Args, 2));
   begin
      Delete (Cur.all, Natural'Min (A, B), Natural'Max (A, B));
      return None;
   end B_Delete_Region;

   function B_Buffer_Substring (Args : Arg_Array) return Value is
      A : constant Natural := Position (Int_Arg (Args, 1));
      B : constant Natural := Position (Int_Arg (Args, 2));
   begin
      return Make_Str (To_String (Text_Of (Cur.all, Natural'Min (A, B), Natural'Max (A, B))));
   end B_Buffer_Substring;

   function B_Buffer_Text (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Str (To_String (Text_Of (Cur.all, 0, Length (Cur.all))));
   end B_Buffer_Text;

   function B_Char_After (Args : Arg_Array) return Value is
      P : constant Natural := Pos_Arg (Args, 1, Cur.Point);
   begin
      return Make_Char (if P < Length (Cur.all) then Char_At (Cur.all, P) else L1.NUL);
   end B_Char_After;

   function B_Char_Before (Args : Arg_Array) return Value is
      P : constant Natural := Pos_Arg (Args, 1, Cur.Point);
   begin
      return Make_Char (if P > 0 then Char_At (Cur.all, P - 1) else L1.NUL);
   end B_Char_Before;

   function B_Current_Line (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
      B : Buffer renames Cur.all;
   begin
      return Make_Str (Slice (B, Line_Start (B, B.Point), Line_End (B, B.Point)));
   end B_Current_Line;

   function B_Line_Beginning_Position (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Script_Pos (Line_Start (Cur.all, Cur.Point));
   end B_Line_Beginning_Position;

   function B_Line_End_Position (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Script_Pos (Line_End (Cur.all, Cur.Point));
   end B_Line_End_Position;

   function B_Current_Column (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Int (Long_Long_Integer (Column_Of (Cur.all, Cur.Point)));
   end B_Current_Column;

   function B_Line_Number (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Int (Long_Long_Integer (Line_Number (Cur.all, Cur.Point)));
   end B_Line_Number;

   function B_Looking_At (Args : Arg_Array) return Value is
      B       : Buffer renames Cur.all;
      Pattern : constant String := Str_Arg (Args, 1);
   begin
      return Make_Bool
        (B.Point + Pattern'Length <= Length (B)
         and then Slice (B, B.Point, B.Point + Pattern'Length) = Pattern);
   end B_Looking_At;

   function B_Search_Forward (Args : Arg_Array) return Value is
      B       : Buffer renames Cur.all;
      Pattern : constant String := Str_Arg (Args, 1);
      Fold    : constant Boolean := Given (Args, 2) and then Bool_Arg (Args, 2);
      R       : Integer;
   begin
      if Pattern = "" then
         Fail ("the pattern is empty");
      end if;
      R := Search_Forward (B, Pattern, B.Point, Fold);
      if R < 0 then
         return Make_Bool (False);
      end if;
      B.Point := R + Pattern'Length;
      return Make_Bool (True);
   end B_Search_Forward;

   function B_Search_Backward (Args : Arg_Array) return Value is
      B       : Buffer renames Cur.all;
      Pattern : constant String := Str_Arg (Args, 1);
      Fold    : constant Boolean := Given (Args, 2) and then Bool_Arg (Args, 2);
      R       : Integer;
   begin
      if Pattern = "" then
         Fail ("the pattern is empty");
      end if;
      R := Search_Backward (B, Pattern, B.Point - Pattern'Length, Fold);
      if R < 0 then
         return Make_Bool (False);
      end if;
      B.Point := R;
      return Make_Bool (True);
   end B_Search_Backward;

   -------------------------------------------------------------------------
   --  Mark and region
   -------------------------------------------------------------------------

   function B_Mark (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      if Region_Needed then
         return Script_Pos (Cur.Mark);
      end if;
      return None;
   end B_Mark;

   function B_Set_Mark (Args : Arg_Array) return Value is
   begin
      Cur.Mark := Pos_Arg (Args, 1, Cur.Point);
      Cur.Mark_Set := True;
      return None;
   end B_Set_Mark;

   function B_Region_Beginning (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      if Region_Needed then
         return Script_Pos (Natural'Min (Cur.Point, Cur.Mark));
      end if;
      return None;
   end B_Region_Beginning;

   function B_Region_End (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      if Region_Needed then
         return Script_Pos (Natural'Max (Cur.Point, Cur.Mark));
      end if;
      return None;
   end B_Region_End;

   -------------------------------------------------------------------------
   --  Buffers, files, messages, keys
   -------------------------------------------------------------------------

   function B_Buffer_Name (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Str (To_String (Cur.Name));
   end B_Buffer_Name;

   function B_File_Name (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Str (To_String (Cur.File_Name));
   end B_File_Name;

   function B_Modified (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Bool (Cur.Modified);
   end B_Modified;

   function B_Visit_File (Args : Arg_Array) return Value is
      B : constant Buffer_Access := File_Commands.Visit_File (Str_Arg (Args, 1));
   begin
      if B = null then
         Fail (Minibuffer.Current_Message);
      end if;
      File_Commands.Switch_To (B);
      return None;
   end B_Visit_File;

   function B_Select_Buffer (Args : Arg_Array) return Value is
      Name : constant String := Str_Arg (Args, 1);
      B    : Buffer_Access := Buffer_List.Find (Name);
   begin
      if B = null then
         B := Buffer_List.Create (Name);
      end if;
      File_Commands.Switch_To (B);
      return None;
   end B_Select_Buffer;

   function B_Message (Args : Arg_Array) return Value is
   begin
      Minibuffer.Message (To_Display (Args (1)));
      return None;
   end B_Message;

   function B_Read_String (Args : Arg_Array) return Value is
      Default : constant String := (if Given (Args, 2) then Str_Arg (Args, 2) else "");
      Result  : Unbounded_String;
      Ok      : Boolean;
   begin
      Minibuffer.Read_String (Str_Arg (Args, 1), "", Result, Ok);
      if not Ok then
         Fail ("Quit");
      end if;
      return Make_Str (if Length (Result) = 0 then Default else To_String (Result));
   end B_Read_String;

   function B_Yes_Or_No (Args : Arg_Array) return Value is
   begin
      case Minibuffer.Ask (Str_Arg (Args, 1)) is
         when Minibuffer.Yes    => return Make_Bool (True);
         when Minibuffer.No     => return Make_Bool (False);
         when Minibuffer.Cancel => Fail ("Quit");
      end case;
   end B_Yes_Or_No;

   function B_Bind_Key (Args : Arg_Array) return Value is
   begin
      Keymaps.Bind (Keymaps.Global_Map, Str_Arg (Args, 1), Str_Arg (Args, 2));
      return None;
   exception
      when E : Keymaps.Parse_Error =>
         Fail (Ada.Exceptions.Exception_Message (E));
   end B_Bind_Key;

   function B_Run_Command (Args : Arg_Array) return Value is
      Name  : constant String := Commands.Normalize (Str_Arg (Args, 1));
      Count : constant Long_Long_Integer := (if Given (Args, 2) then Int_Arg (Args, 2) else 1);
   begin
      if not Commands.Exists (Name) then
         Fail ("no command named " & Name);
      elsif Count not in 1 .. 1_000_000 then
         Fail ("the count must be in 1 .. 1000000");
      end if;
      Run_Editor_Command (Name, Positive (Count), Given (Args, 2));
      return None;
   end B_Run_Command;

   function B_Command_Exists (Args : Arg_Array) return Value is
     (Make_Bool (Commands.Exists (Str_Arg (Args, 1))));

   function B_Set_Tab_Width (Args : Arg_Array) return Value is
      N : constant Long_Long_Integer := Int_Arg (Args, 1);
   begin
      if N not in 1 .. 32 then
         Fail ("the tab width must be in 1 .. 32");
      end if;
      Buffers.Tab_Width := Positive (N);
      Display.Invalidate;
      return None;
   end B_Set_Tab_Width;

   -------------------------------------------------------------------------
   --  Strings
   -------------------------------------------------------------------------

   function Map_Case (Args : Arg_Array; Upper : Boolean) return Value is
      function Conv (C : Character) return Character is
        (if Upper then Utils.To_Upper (C) else Utils.To_Lower (C));
   begin
      case Args (1).Kind is
         when V_Character =>
            return Make_Char (Conv (Args (1).Char));
         when V_String =>
            declare
               S : String := To_String (Args (1).Str);
            begin
               for C of S loop
                  C := Conv (C);
               end loop;
               return Make_Str (S);
            end;
         when others =>
            Fail ("argument 1 must be String or Character, not " & Kind_Name (Args (1)));
      end case;
   end Map_Case;

   function B_Upcase (Args : Arg_Array) return Value is (Map_Case (Args, True));
   function B_Downcase (Args : Arg_Array) return Value is (Map_Case (Args, False));

   function B_Index (Args : Arg_Array) return Value is
      Source  : constant String := Str_Arg (Args, 1);
      Pattern : constant String := Str_Arg (Args, 2);
      From    : constant Long_Long_Integer := (if Given (Args, 3) then Int_Arg (Args, 3) else 1);
   begin
      if Pattern = "" then
         Fail ("the pattern is empty");
      elsif From < 1 or else From > Long_Long_Integer (Source'Length) + 1 then
         Fail ("From is outside the string");
      elsif From > Long_Long_Integer (Source'Length) then
         return Make_Int (0);
      end if;
      return Make_Int (Long_Long_Integer
                         (Ada.Strings.Fixed.Index (Source, Pattern, Positive (From))));
   end B_Index;

   Whitespace : constant Ada.Strings.Maps.Character_Set :=
     Ada.Strings.Maps.To_Set (" " & L1.HT & L1.LF & L1.CR & L1.FF);

   function B_Trim (Args : Arg_Array) return Value is
     (Make_Str (Ada.Strings.Fixed.Trim (Str_Arg (Args, 1), Whitespace, Whitespace)));

   function B_Length (Args : Arg_Array) return Value is
   begin
      if Args (1).Kind = V_Vector then
         return Make_Int (Long_Long_Integer (Item_Count (Args (1))));
      end if;
      return Make_Int (Long_Long_Integer (Str_Arg (Args, 1)'Length));
   end B_Length;

   -------------------------------------------------------------------------
   --  Vectors and exceptions
   -------------------------------------------------------------------------

   function Vector_Arg (Args : Arg_Array; I : Positive) return Value is
   begin
      if Args (I).Kind /= V_Vector then
         Fail ("argument " & Utils.Img (I) & " must be a Vector, not " & Kind_Name (Args (I)));
      end if;
      return Args (I);
   end Vector_Arg;

   function B_Split (Args : Arg_Array) return Value is
      Source : constant String := Str_Arg (Args, 1);
      Result : Value := Make_Vector;
   begin
      if not Given (Args, 2) then
         --  Words separated by blanks
         declare
            I : Integer := Source'First;
            J : Integer;
         begin
            loop
               while I <= Source'Last and then Source (I) in ' ' | L1.HT | L1.LF | L1.CR loop
                  I := I + 1;
               end loop;
               exit when I > Source'Last;
               J := I;
               while J <= Source'Last and then Source (J) not in ' ' | L1.HT | L1.LF | L1.CR loop
                  J := J + 1;
               end loop;
               Append (Result, Make_Str (Source (I .. J - 1)));
               I := J;
            end loop;
         end;
      else
         declare
            Separator : constant String := Str_Arg (Args, 2);
            Start     : Integer := Source'First;
            P         : Natural;
         begin
            if Separator = "" then
               Fail ("the separator is empty");
            end if;
            loop
               P := Ada.Strings.Fixed.Index (Source (Start .. Source'Last), Separator);
               if P = 0 then
                  Append (Result, Make_Str (Source (Start .. Source'Last)));
                  exit;
               end if;
               Append (Result, Make_Str (Source (Start .. P - 1)));
               Start := P + Separator'Length;
            end loop;
         end;
      end if;
      return Result;
   end B_Split;

   function B_Join (Args : Arg_Array) return Value is
      Items     : constant Value := Vector_Arg (Args, 1);
      Separator : constant String := (if Given (Args, 2) then Str_Arg (Args, 2) else "");
      Result    : Unbounded_String;
   begin
      for I in 1 .. Item_Count (Items) loop
         declare
            E : constant Value := Element (Items, I);
         begin
            if E.Kind not in V_String | V_Character then
               Fail ("element " & Utils.Img (I) & " is " & Kind_Name (E) & ", not String");
            end if;
            if I > 1 then
               Append (Result, Separator);
            end if;
            Append (Result, To_Display (E));
         end;
      end loop;
      return Make_Str (To_String (Result));
   end B_Join;

   function B_Contains (Args : Arg_Array) return Value is
      Items : constant Value := Vector_Arg (Args, 1);
   begin
      for I in 1 .. Item_Count (Items) loop
         if Equal (Element (Items, I), Args (2)) then
            return Make_Bool (True);
         end if;
      end loop;
      return Make_Bool (False);
   end B_Contains;

   function B_Sort (Args : Arg_Array) return Value is
      Items : constant Value := Vector_Arg (Args, 1);

      function Less (A, B : Value) return Boolean is
        (case A.Kind is
            when V_Integer   => A.Int < B.Int,
            when V_Character => A.Char < B.Char,
            when V_String    => A.Str < B.Str,
            when others      => False);

      package Sorting is new Value_Vectors.Generic_Sorting ("<" => Less);

      Result : Value := Make_Vector;
   begin
      for I in 1 .. Item_Count (Items) loop
         declare
            E : constant Value := Element (Items, I);
         begin
            if E.Kind not in V_Integer | V_Character | V_String
              or else E.Kind /= Element (Items, 1).Kind
            then
               Fail ("Sort needs a vector of Integers, Characters or Strings of one kind");
            end if;
            Append (Result, E);
         end;
      end loop;
      Sorting.Sort (Result.Items.Data.Values);
      return Result;
   end B_Sort;

   function B_Exception_Name (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      if Scripts.Interpreter.Current_Exception_Name = "" then
         Fail ("not in an exception handler");
      end if;
      return Make_Str (Scripts.Interpreter.Current_Exception_Name);
   end B_Exception_Name;

   function B_Exception_Message (Args : Arg_Array) return Value is
   begin
      if Given (Args, 1) then
         return Make_Str (Str_Arg (Args, 1));
      elsif Scripts.Interpreter.Current_Exception_Name = "" then
         Fail ("not in an exception handler");
      end if;
      return Make_Str (Scripts.Interpreter.Current_Exception_Message);
   end B_Exception_Message;

   function B_Image (Args : Arg_Array) return Value is
     (Make_Str (To_Display (Args (1))));

   function B_Getenv (Args : Arg_Array) return Value is
      Name : constant String := Str_Arg (Args, 1);
   begin
      if Ada.Environment_Variables.Exists (Name) then
         return Make_Str (Ada.Environment_Variables.Value (Name));
      end if;
      return Make_Str ("");
   end B_Getenv;

   -------------------------------------------------------------------------

   -------------------------------------------------------------------------
   --  Modes, faces, compiling
   -------------------------------------------------------------------------

   function Mode_Arg (Args : Arg_Array; I : Positive) return Mode_Kind is
      Found : Boolean;
      M     : constant Mode_Kind := Modes.Mode_Of_Name (Str_Arg (Args, I), Found);
   begin
      if not Found then
         Fail ("unknown mode " & Str_Arg (Args, I));
      end if;
      return M;
   end Mode_Arg;

   function B_Mode_Name (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Str (Syntax.Mode_Name (Cur.Mode));
   end B_Mode_Name;

   function B_Set_Mode (Args : Arg_Array) return Value is
   begin
      Modes.Set_Mode (Cur, Mode_Arg (Args, 1));
      return None;
   end B_Set_Mode;

   function B_Bind_Mode_Key (Args : Arg_Array) return Value is
   begin
      Keymaps.Bind (Keymaps.Mode_Map (Mode_Arg (Args, 1)), Str_Arg (Args, 2), Str_Arg (Args, 3));
      return None;
   exception
      when E : Keymaps.Parse_Error =>
         Fail (Ada.Exceptions.Exception_Message (E));
   end B_Bind_Mode_Key;

   function B_Set_Face (Args : Arg_Array) return Value is
      Ok : Boolean;
   begin
      Syntax.Set_Face (Str_Arg (Args, 1), Str_Arg (Args, 2), Ok);
      if not Ok then
         Fail ("unknown face or bad colour code (faces: keyword, comment, string, "
               & "number, error, warning, status; codes like ""1;34"")");
      end if;
      Display.Invalidate;
      return None;
   end B_Set_Face;

   function B_Set_Indent_Width (Args : Arg_Array) return Value is
      N : constant Long_Long_Integer := Int_Arg (Args, 1);
   begin
      if N not in 1 .. 16 then
         Fail ("the indent width must be in 1 .. 16");
      end if;
      Ada_Indent.Indent_Width := Positive (N);
      return None;
   end B_Set_Indent_Width;

   function B_Define_Mode (Args : Arg_Array) return Value is
      function Text (I : Positive) return Unbounded_String is
        (if Given (Args, I) then To_Unbounded_String (Str_Arg (Args, I))
         else Null_Unbounded_String);
      Name : constant String := Str_Arg (Args, 1);
      Def  : Mode_Defs.Mode_Def;
      Id   : Mode_Kind;
   begin
      if Name = "" then
         Fail ("the mode name is empty");
      elsif Mode_Defs.Find (Name) in 1 .. Compilation_Mode then
         Fail ("cannot redefine the built-in mode " & Name);
      end if;
      Def.Name := To_Unbounded_String (Name);
      Def.Title := Text (2);
      Def.Extensions := Text (3);
      Def.Keywords := Text (4);
      Def.Types := Text (5);
      Def.Line_Comment := Text (6);
      Def.Block_Comment_Start := Text (7);
      Def.Block_Comment_End := Text (8);
      Def.Backslash_Escapes := Given (Args, 9) and then Bool_Arg (Args, 9);
      Def.Case_Sensitive := not Given (Args, 10) or else Bool_Arg (Args, 10);
      Def.Formatter := Text (11);
      Def.Highlighter := Mode_Defs.Generic_Highlighting;
      Id := Mode_Defs.Define (Def);

      --  Buffers already visiting matching files switch to the new mode
      for I in 1 .. Buffer_List.Count loop
         declare
            B : constant Buffer_Access := Buffer_List.Get (I);
         begin
            if B.Mode = Fundamental_Mode and then Length (B.File_Name) > 0
              and then Mode_Defs.For_File (To_String (B.File_Name)) = Id
            then
               Modes.Set_Mode (B, Id);
            end if;
         end;
      end loop;
      Display.Invalidate;
      return None;
   end B_Define_Mode;

   function B_Line_Count (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Int (Long_Long_Integer (Line_Number (Cur.all, Length (Cur.all))));
   end B_Line_Count;

   function B_Line_Text (Args : Arg_Array) return Value is
      N    : constant Long_Long_Integer := Int_Arg (Args, 1);
      B    : Buffer renames Cur.all;
      Last : constant Positive := Line_Number (B, Length (B));
   begin
      if N < 1 or else N > Long_Long_Integer (Last) then
         Fail ("line" & Long_Long_Integer'Image (N) & " is outside 1 .." & Positive'Image (Last));
      end if;
      declare
         P : constant Natural := Pos_Of_Line (B, Positive (N));
      begin
         return Make_Str (Slice (B, P, Line_End (B, P)));
      end;
   end B_Line_Text;

   function B_Current_Indentation (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
      B : Buffer renames Cur.all;
      P : Natural := Line_Start (B, B.Point);
   begin
      while P < Length (B) and then Char_At (B, P) in ' ' | L1.HT loop
         P := P + 1;
      end loop;
      return Make_Int (Long_Long_Integer (Column_Of (B, P)));
   end B_Current_Indentation;

   function B_Indent_To (Args : Arg_Array) return Value is
      N : constant Long_Long_Integer := Int_Arg (Args, 1);
   begin
      if N not in 0 .. 1000 then
         Fail ("the column must be in 0 .. 1000");
      end if;
      Ada_Indent.Indent_Line_To (Cur.all, Natural (N));
      return None;
   end B_Indent_To;

   function B_Load (Args : Arg_Array) return Value is
      Full : constant String := File_Names.Absolute (Str_Arg (Args, 1));
   begin
      Scripts.Interpreter.Load_File (Full, File_Names.Abbreviate (Full));
      return None;
   end B_Load;

   -------------------------------------------------------------------------
   --  Regular expressions
   -------------------------------------------------------------------------

   Last_Match : Regex_Search.Match_Result;

   function Re_Search (Args : Arg_Array; Forward : Boolean) return Value is
      B       : Buffer renames Cur.all;
      Pattern : constant String := Str_Arg (Args, 1);
      Fold    : constant Boolean := Given (Args, 2) and then Bool_Arg (Args, 2);
      M       : Regex_Search.Match_Result;
   begin
      M := (if Forward then Regex_Search.Search_Forward (B, Pattern, B.Point, Fold)
            else Regex_Search.Search_Backward (B, Pattern, B.Point - 1, Fold));
      if not M.Found then
         return Make_Bool (False);
      end if;
      Last_Match := M;
      B.Point := (if Forward then M.Groups (0).Stop else M.Groups (0).Start);
      return Make_Bool (True);
   exception
      when E : Regex_Search.Invalid_Pattern =>
         Fail ("invalid regexp: " & Ada.Exceptions.Exception_Message (E));
   end Re_Search;

   function B_Re_Search_Forward (Args : Arg_Array) return Value is (Re_Search (Args, True));
   function B_Re_Search_Backward (Args : Arg_Array) return Value is (Re_Search (Args, False));

   function Match_Group (Args : Arg_Array) return Regex_Search.Group is
      N : constant Long_Long_Integer := (if Given (Args, 1) then Int_Arg (Args, 1) else 0);
   begin
      if not Last_Match.Found then
         Fail ("there was no successful regexp search");
      elsif N not in 0 .. Regex_Search.Max_Groups then
         Fail ("the group must be in 0 .." & Integer'Image (Regex_Search.Max_Groups));
      elsif not Last_Match.Groups (Integer (N)).Matched then
         Fail ("group" & Long_Long_Integer'Image (N) & " did not match");
      end if;
      return Last_Match.Groups (Integer (N));
   end Match_Group;

   function B_Match_Beginning (Args : Arg_Array) return Value is
     (Script_Pos (Match_Group (Args).Start));

   function B_Match_End (Args : Arg_Array) return Value is
     (Script_Pos (Match_Group (Args).Stop));

   function B_Match_String (Args : Arg_Array) return Value is
      G : constant Regex_Search.Group := Match_Group (Args);
   begin
      if G.Stop > Length (Cur.all) then
         Fail ("the buffer changed since the search");
      end if;
      return Make_Str (Slice (Cur.all, G.Start, G.Stop));
   end B_Match_String;

   function B_Set_Formatter (Args : Arg_Array) return Value is
   begin
      Mode_Defs.Set_Formatter (Mode_Arg (Args, 1), Str_Arg (Args, 2));
      return None;
   end B_Set_Formatter;

   function B_Shell_Output (Args : Arg_Array) return Value is
     (Make_Str (Shell_Commands.Command_Output (Str_Arg (Args, 1))));

   function B_Set_Fill_Column (Args : Arg_Array) return Value is
      N : constant Long_Long_Integer := Int_Arg (Args, 1);
   begin
      if N not in 1 .. 10_000 then
         Fail ("the fill column must be in 1 .. 10000");
      end if;
      Buffers.Fill_Column := Positive (N);
      return None;
   end B_Set_Fill_Column;

   function B_Set_Backups (Args : Arg_Array) return Value is
   begin
      Buffers.Make_Backups := Bool_Arg (Args, 1);
      return None;
   end B_Set_Backups;

   function B_Set_Startup_Screen (Args : Arg_Array) return Value is
   begin
      Commands.Startup_Screen := Bool_Arg (Args, 1);
      return None;
   end B_Set_Startup_Screen;

   function B_Set_Read_Only (Args : Arg_Array) return Value is
   begin
      Cur.Read_Only := Bool_Arg (Args, 1);
      return None;
   end B_Set_Read_Only;

   function B_Read_Only (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Bool (Cur.Read_Only);
   end B_Read_Only;

   function B_Set_Line_Numbers (Args : Arg_Array) return Value is
      Enabled : constant Boolean := Bool_Arg (Args, 1);
   begin
      Buffers.Line_Numbers_Default := Enabled;
      for I in 1 .. Buffer_List.Count loop
         Buffer_List.Get (I).Line_Numbers := Enabled;
      end loop;
      return None;
   end B_Set_Line_Numbers;

   function B_Set_Confirm_Exit (Args : Arg_Array) return Value is
   begin
      Commands.Confirm_Exit := Bool_Arg (Args, 1);
      return None;
   end B_Set_Confirm_Exit;

   function B_Set_Auto_Save (Args : Arg_Array) return Value is
   begin
      if Given (Args, 1) then
         if Int_Arg (Args, 1) not in 1 .. 1_000_000 then
            Fail ("Keys must be in 1 .. 1000000");
         end if;
         Auto_Save.Interval_Keys := Positive (Int_Arg (Args, 1));
      end if;
      if Given (Args, 2) then
         if Int_Arg (Args, 2) not in 1 .. 86_400 then
            Fail ("Idle_Seconds must be in 1 .. 86400");
         end if;
         Auto_Save.Idle_Seconds := Positive (Int_Arg (Args, 2));
      end if;
      return None;
   end B_Set_Auto_Save;

   function B_Last_Command (Args : Arg_Array) return Value is
      pragma Unreferenced (Args);
   begin
      return Make_Str (To_String (Commands.Last_Command));
   end B_Last_Command;

   function B_Start_Compile (Args : Arg_Array) return Value is
   begin
      Compile_Commands.Start (Str_Arg (Args, 1));
      return None;
   end B_Start_Compile;

   procedure Register_All is
   begin
      Define ("mode_name", "", 0, B_Mode_Name'Access);
      Define ("set_mode", "mode", 1, B_Set_Mode'Access);
      Define ("bind_mode_key", "mode,keys,command", 3, B_Bind_Mode_Key'Access);
      Define ("set_face", "face,code", 2, B_Set_Face'Access);
      Define ("set_indent_width", "width", 1, B_Set_Indent_Width'Access);
      Define ("start_compile", "command", 1, B_Start_Compile'Access);
      Define ("define_mode",
              "name,title,extensions,keywords,types,line_comment,"
              & "block_comment_start,block_comment_end,backslash_escapes,case_sensitive,"
              & "formatter",
              1, B_Define_Mode'Access);
      Define ("line_count", "", 0, B_Line_Count'Access);
      Define ("line_text", "line", 1, B_Line_Text'Access);
      Define ("current_indentation", "", 0, B_Current_Indentation'Access);
      Define ("indent_to", "column", 1, B_Indent_To'Access);
      Define ("load", "file", 1, B_Load'Access);
      Define ("last_command", "", 0, B_Last_Command'Access);
      Define ("set_backups", "enabled", 1, B_Set_Backups'Access);
      Define ("set_confirm_exit", "enabled", 1, B_Set_Confirm_Exit'Access);
      Define ("set_line_numbers", "enabled", 1, B_Set_Line_Numbers'Access);
      Define ("set_startup_screen", "enabled", 1, B_Set_Startup_Screen'Access);
      Define ("set_read_only", "enabled", 1, B_Set_Read_Only'Access);
      Define ("read_only", "", 0, B_Read_Only'Access);
      Define ("set_auto_save", "keys,idle_seconds", 0, B_Set_Auto_Save'Access);
      Define ("re_search_forward", "pattern,ignore_case", 1, B_Re_Search_Forward'Access);
      Define ("re_search_backward", "pattern,ignore_case", 1, B_Re_Search_Backward'Access);
      Define ("match_beginning", "group", 0, B_Match_Beginning'Access);
      Define ("match_end", "group", 0, B_Match_End'Access);
      Define ("match_string", "group", 0, B_Match_String'Access);
      Define ("set_fill_column", "column", 1, B_Set_Fill_Column'Access);
      Define ("shell_output", "command", 1, B_Shell_Output'Access);
      Define ("set_formatter", "mode,command", 2, B_Set_Formatter'Access);
      Define ("split", "source,separator", 1, B_Split'Access);
      Define ("join", "items,separator", 1, B_Join'Access);
      Define ("contains", "items,item", 2, B_Contains'Access);
      Define ("sort", "items", 1, B_Sort'Access);
      Define ("exception_name", "", 0, B_Exception_Name'Access);
      Define ("exception_message", "occurrence", 0, B_Exception_Message'Access);

      Define ("point", "", 0, B_Point'Access);
      Define ("point_min", "", 0, B_Point_Min'Access);
      Define ("point_max", "", 0, B_Point_Max'Access);
      Define ("buffer_size", "", 0, B_Buffer_Size'Access);
      Define ("goto_char", "position", 1, B_Goto_Char'Access);
      Define ("insert", "text", 1, B_Insert'Access);
      Define ("delete_region", "from,to", 2, B_Delete_Region'Access);
      Define ("buffer_substring", "from,to", 2, B_Buffer_Substring'Access);
      Define ("buffer_text", "", 0, B_Buffer_Text'Access);
      Define ("char_after", "position", 0, B_Char_After'Access);
      Define ("char_before", "position", 0, B_Char_Before'Access);
      Define ("current_line", "", 0, B_Current_Line'Access);
      Define ("line_beginning_position", "", 0, B_Line_Beginning_Position'Access);
      Define ("line_end_position", "", 0, B_Line_End_Position'Access);
      Define ("current_column", "", 0, B_Current_Column'Access);
      Define ("line_number", "", 0, B_Line_Number'Access);
      Define ("looking_at", "text", 1, B_Looking_At'Access);
      Define ("search_forward", "pattern,ignore_case", 1, B_Search_Forward'Access);
      Define ("search_backward", "pattern,ignore_case", 1, B_Search_Backward'Access);

      Define ("mark", "", 0, B_Mark'Access);
      Define ("set_mark", "position", 0, B_Set_Mark'Access);
      Define ("region_beginning", "", 0, B_Region_Beginning'Access);
      Define ("region_end", "", 0, B_Region_End'Access);

      Define ("buffer_name", "", 0, B_Buffer_Name'Access);
      Define ("file_name", "", 0, B_File_Name'Access);
      Define ("modified", "", 0, B_Modified'Access);
      Define ("visit_file", "name", 1, B_Visit_File'Access);
      Define ("select_buffer", "name", 1, B_Select_Buffer'Access);
      Define ("message", "text", 1, B_Message'Access);
      Define ("read_string", "prompt,default", 1, B_Read_String'Access);
      Define ("yes_or_no", "prompt", 1, B_Yes_Or_No'Access);
      Define ("bind_key", "keys,command", 2, B_Bind_Key'Access);
      Define ("run_command", "name,count", 1, B_Run_Command'Access);
      Define ("command_exists", "name", 1, B_Command_Exists'Access);
      Define ("set_tab_width", "width", 1, B_Set_Tab_Width'Access);

      Define ("upcase", "item", 1, B_Upcase'Access);
      Define ("downcase", "item", 1, B_Downcase'Access);
      Define ("index", "source,pattern,from", 2, B_Index'Access);
      Define ("trim", "source", 1, B_Trim'Access);
      Define ("length", "source", 1, B_Length'Access);
      Define ("image", "item", 1, B_Image'Access);
      Define ("getenv", "name", 1, B_Getenv'Access);
   end Register_All;

end Scripts.Builtins;
