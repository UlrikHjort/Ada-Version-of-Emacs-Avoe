-- ***************************************************************************
--                         Avoe - Scripts.Interpreter
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
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Buffers;
with Commands;
with Minibuffer;
with Scripts.AST;      use Scripts.AST;
with Scripts.Builtins;
with Scripts.Lexer;    use Scripts.Lexer;
with Scripts.Parser;
with Scripts.Values;   use Scripts.Values;
with String_Vectors;
with Terminal;
with Utils;

package body Scripts.Interpreter is

   package L1 renames Ada.Characters.Latin_1;

   type Variable is record
      Val         : Value;
      Decl_Type   : Type_Name := T_Any;
      Is_Constant : Boolean := False;
   end record;

   package Var_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Variable, Ada.Strings.Hash, "=");
   package Sub_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Node_Access, Ada.Strings.Hash, "=");

   --  Variables live in two scopes: the globals, and the locals of the
   --  subprogram that is running.  A name that is not local is global.
   type Env_Access is access all Var_Maps.Map;

   Globals     : aliased Var_Maps.Map;
   Global_Env  : constant Env_Access := Globals'Access;
   Subprograms : Sub_Maps.Map;

   --  Max_Depth limits nested calls; Steps counts statements between the
   --  checks for C-g
   Max_Depth   : constant := 200;
   Depth       : Natural := 0;
   Steps       : Natural := 0;

   --  How statements ended: normally, by exit (leaving the innermost loop)
   --  or by return (the value is in Return_Value)
   type Flow is (Normal, Exit_Loop, Return_From);

   Return_Value : Value;

   type Node_Array is array (Positive range <>) of Node_Access;

   --  Exceptions raised by scripts ("raise Name with Message").  The details
   --  are kept here, since Ada exception messages are limited in length.
   Script_Raise   : exception;
   Raised_Name    : Unbounded_String;
   Raised_Message : Unbounded_String;
   Raised_Where   : Unbounded_String;

   Interrupted : exception;
   --  C-g: not catchable by scripts

   type Handled is record
      Name    : Unbounded_String;
      Message : Unbounded_String;
   end record;

   package Handled_Vectors is new Ada.Containers.Vectors (Positive, Handled);

   Handling : Handled_Vectors.Vector;
   --  The exceptions whose handlers are running, innermost last

   procedure Fail (N : Node_Access; Msg : String) with No_Return;

   procedure Fail (N : Node_Access; Msg : String) is
   begin
      raise Script_Error with Where (N) & ": " & Msg;
   end Fail;

   function Eval (N : Node_Access; Env : Env_Access) return Value;
   function Exec_List (List : Node_Vectors.Vector; Env : Env_Access) return Flow;
   function Exec_Guarded
     (Stmts, Handlers : Node_Vectors.Vector; Env : Env_Access) return Flow;

   -------------------------------------------------------------------------
   --  Variables
   -------------------------------------------------------------------------

   --  Editor.Insert and ASCII.LF are accepted too, for Ada familiarity
   function Strip_Package (Name : String) return String is
   begin
      if Utils.Starts_With (Name, "editor.") then
         return Name (Name'First + 7 .. Name'Last);
      elsif Utils.Starts_With (Name, "ascii.") then
         return Name (Name'First + 6 .. Name'Last);
      end if;
      return Name;
   end Strip_Package;

   function Get_Var (Env : Env_Access; Name : String; Found : out Boolean) return Value is
      C : Var_Maps.Cursor := Env.Find (Name);
   begin
      if not Var_Maps.Has_Element (C) and then Env /= Global_Env then
         C := Globals.Find (Name);
      end if;
      Found := Var_Maps.Has_Element (C);
      return (if Found then Var_Maps.Element (C).Val else None);
   end Get_Var;

   function Var_Exists (Env : Env_Access; Name : String) return Boolean is
     (Env.Contains (Name) or else Globals.Contains (Name));

   --  The value of a variable, or of a record field path such as "p.x.y"
   function Get_Path
     (N     : Node_Access;
      Env   : Env_Access;
      Name  : String;
      Found : out Boolean) return Value
   is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Name, ".");
   begin
      declare
         V : constant Value := Get_Var (Env, Name, Found);
      begin
         if Found or else Dot = 0 then
            return V;
         end if;
      end;

      declare
         Current : Value := Get_Var (Env, Name (Name'First .. Dot - 1), Found);
         Start   : Positive := Dot + 1;
         Stop    : Natural;
      begin
         if not Found then
            return None;
         end if;
         loop
            Stop := Ada.Strings.Fixed.Index (Name (Start .. Name'Last), ".");
            Stop := (if Stop = 0 then Name'Last else Stop - 1);
            declare
               Field : constant String := Name (Start .. Stop);
               Owner : constant String := Name (Name'First .. Start - 2);
               I     : Natural;
            begin
               if Current.Kind /= V_Record then
                  Fail (N, Owner & " is " & Kind_Name (Current) & ", not a record");
               end if;
               I := Find_Field (Current, Field);
               if I = 0 then
                  Fail (N, Owner & " has no field " & Field);
               end if;
               Current := Element (Current, I);
            end;
            exit when Stop = Name'Last;
            Start := Stop + 2;
         end loop;
         return Current;
      end;
   end Get_Path;

   procedure Check_Type (N : Node_Access; T : Type_Name; V : Value; What : String) is
   begin
      if Accepts (T, V) then
         return;
      end if;
      if T in T_Natural | T_Positive and then V.Kind = V_Integer then
         Fail (N, "value " & To_Display (V) & " is out of range for " & What
               & " (" & Type_Image (T) & ")");
      end if;
      Fail (N, What & " is " & Type_Image (T) & " but the value is " & Kind_Name (V));
   end Check_Type;

   procedure Assign (Env : Env_Access; N : Node_Access; Name : String; V : Value) is

      procedure Store (M : Env_Access) is
         C   : constant Var_Maps.Cursor := M.Find (Name);
         Var : Variable := Var_Maps.Element (C);
      begin
         if Var.Is_Constant then
            Fail (N, "cannot assign to constant " & Name);
         end if;
         Check_Type (N, Var.Decl_Type, V, Name);
         Var.Val := V;
         M.Replace_Element (C, Var);
      end Store;

   begin
      if Env.Contains (Name) then
         Store (Env);
      elsif Globals.Contains (Name) then
         Store (Global_Env);
      else
         --  Declarations are optional: a new name becomes a variable here
         Env.Insert (Name, (Val => V, others => <>));
      end if;
   end Assign;

   function Eval_Bool (N : Node_Access; Env : Env_Access) return Boolean is
      V : constant Value := Eval (N, Env);
   begin
      if V.Kind /= V_Boolean then
         Fail (N, "expected a Boolean but got " & Kind_Name (V));
      end if;
      return V.Bool;
   end Eval_Bool;

   function Eval_Int (N : Node_Access; Env : Env_Access) return Long_Long_Integer is
      V : constant Value := Eval (N, Env);
   begin
      if V.Kind /= V_Integer then
         Fail (N, "expected an Integer but got " & Kind_Name (V));
      end if;
      return V.Int;
   end Eval_Int;

   function Compare (N : Node_Access; A, B : Value) return Integer is
   begin
      if A.Kind /= B.Kind then
         Fail (N, "cannot compare " & Kind_Name (A) & " with " & Kind_Name (B));
      end if;
      case A.Kind is
         when V_Integer =>
            return (if A.Int < B.Int then -1 elsif A.Int > B.Int then 1 else 0);
         when V_Character =>
            return (if A.Char < B.Char then -1 elsif A.Char > B.Char then 1 else 0);
         when V_String =>
            return (if A.Str < B.Str then -1 elsif A.Str > B.Str then 1 else 0);
         when V_Boolean =>
            return (if A.Bool = B.Bool then 0 elsif B.Bool then -1 else 1);
         when V_Vector | V_Record =>
            Fail (N, "vectors and records can only be compared with = and /=");
         when V_None =>
            Fail (N, "cannot compare things that have no value");
      end case;
   end Compare;

   -------------------------------------------------------------------------
   --  Calls
   -------------------------------------------------------------------------

   function Index_Value (N : Node_Access; V : Value; Env : Env_Access) return Value is
   begin
      if V.Kind not in V_String | V_Vector then
         Fail (N, "a " & Kind_Name (V) & " cannot be indexed");
      elsif Natural (N.List.Length) /= 1 then
         Fail (N, "one index or one range is needed");
      end if;
      declare
         Len : constant Natural :=
           (if V.Kind = V_String then Length (V.Str) else Item_Count (V));
         A   : constant Node_Access := N.List.First_Element;
      begin
         if A.Kind = N_Range then
            declare
               Lo : constant Long_Long_Integer := Eval_Int (A.Left, Env);
               Hi : constant Long_Long_Integer := Eval_Int (A.Right, Env);
            begin
               if Hi < Lo then
                  return (if V.Kind = V_String then Make_Str ("") else Make_Vector);
               elsif Lo < 1 or else Hi > Long_Long_Integer (Len) then
                  Fail (A, "slice" & Long_Long_Integer'Image (Lo) & " .."
                        & Long_Long_Integer'Image (Hi) & " is outside 1 .."
                        & Natural'Image (Len));
               end if;
               return (if V.Kind = V_String
                       then Make_Str (Slice (V.Str, Integer (Lo), Integer (Hi)))
                       else Vector_Slice (V, Positive (Lo), Positive (Hi)));
            end;
         elsif A.Kind = N_Named_Arg then
            Fail (A, "an index cannot be named");
         else
            declare
               I : constant Long_Long_Integer := Eval_Int (A, Env);
            begin
               if I < 1 or else I > Long_Long_Integer (Len) then
                  Fail (A, "index" & Long_Long_Integer'Image (I) & " is outside 1 .."
                        & Natural'Image (Len));
               end if;
               return (if V.Kind = V_String then Make_Char (Element (V.Str, Integer (I)))
                       else Element (V, Positive (I)));
            end;
         end if;
      end;
   end Index_Value;

   procedure Match_Args
     (N     : Node_Access;
      What  : String;
      Names : String_Vectors.Vector;
      Given : out Node_Array)
   is
      Positional : Natural := 0;
      Named_Seen : Boolean := False;
   begin
      Given := (others => null);
      for A of N.List loop
         if A.Kind = N_Named_Arg then
            Named_Seen := True;
            declare
               Idx : constant Natural := Names.Find_Index (To_String (A.Name));
            begin
               if Idx = String_Vectors.No_Index then
                  Fail (A, What & " has no parameter named " & To_String (A.Name));
               elsif Given (Idx) /= null then
                  Fail (A, "parameter " & To_String (A.Name) & " is given twice");
               end if;
               Given (Idx) := A.Left;
            end;
         else
            if Named_Seen then
               Fail (A, "positional argument after a named argument");
            elsif A.Kind = N_Range then
               Fail (A, "a range is not allowed here");
            end if;
            Positional := Positional + 1;
            if Positional > Given'Last then
               Fail (A, "too many arguments in call to " & What);
            end if;
            Given (Positional) := A;
         end if;
      end loop;
   end Match_Args;

   function Call_Script (N : Node_Access; Sub : Node_Access; Env : Env_Access) return Value is
      Name      : constant String := To_String (Sub.Name);
      Count     : constant Natural := Natural (Sub.List.Length);
      Names     : String_Vectors.Vector;
      Given     : Node_Array (1 .. Count);
      Locals    : aliased Var_Maps.Map;
      Local_Env : constant Env_Access := Locals'Unchecked_Access;
      Result    : Flow;
   begin
      for P of Sub.List loop
         Names.Append (To_String (P.Name));
      end loop;
      Match_Args (N, Name, Names, Given);

      for I in 1 .. Count loop
         declare
            P     : constant Node_Access := Sub.List (I);
            Where : constant Node_Access := (if Given (I) = null then N else Given (I));
            V     : Value;
         begin
            if Given (I) = null then
               if P.Left = null or else P.Mode /= Mode_In then
                  Fail (N, "missing argument for " & Names (I) & " in call to " & Name);
               end if;
               --  Default values are evaluated in the global scope
               V := Eval (P.Left, Global_Env);
            elsif P.Mode = Mode_In then
               V := Eval (Given (I), Env);
            else
               if Given (I).Kind /= N_Name then
                  Fail (Given (I), "the argument for '" & Image (K_Out) & "' parameter "
                        & Names (I) & " must be a variable");
               end if;
               declare
                  Found : Boolean;
               begin
                  V := Get_Var (Env, To_String (Given (I).Name), Found);
                  if not Found and then P.Mode = Mode_In_Out then
                     Fail (Given (I), "undefined variable " & To_String (Given (I).Name));
                  end if;
               end;
            end if;

            if P.Mode /= Mode_Out then
               if V.Kind = V_None then
                  Fail (Where, "no value for parameter " & Names (I));
               end if;
               Check_Type (Where, P.Decl_Type, V, "parameter " & Names (I));
            end if;
            Locals.Include
              (Names (I), (Val => V, Decl_Type => P.Decl_Type, Is_Constant => P.Mode = Mode_In));
         end;
      end loop;

      if Depth >= Max_Depth then
         Fail (N, "calls nested too deeply (endless recursion in " & Name & "?)");
      end if;
      Depth := Depth + 1;
      begin
         Result := Exec_Guarded (Sub.Stmts, Sub.Else_Stmts, Local_Env);
      exception
         when others =>
            Depth := Depth - 1;
            raise;
      end;
      Depth := Depth - 1;

      --  out and in out parameters are copied back to the caller's variables
      for I in 1 .. Count loop
         if Sub.List (I).Mode /= Mode_In and then Given (I) /= null then
            declare
               V : constant Value := Locals.Element (Names (I)).Val;
            begin
               if V.Kind /= V_None then
                  Assign (Env, Given (I), To_String (Given (I).Name), V);
               end if;
            end;
         end if;
      end loop;

      if Sub.Flag then
         if Result /= Return_From or else Return_Value.Kind = V_None then
            Fail (N, "function " & Name & " ended without returning a value");
         end if;
         Check_Type (N, Sub.Decl_Type, Return_Value, "the result of " & Name);
         return Return_Value;
      elsif Result = Return_From and then Return_Value.Kind /= V_None then
         Fail (N, "procedure " & Name & " cannot return a value");
      end if;
      return None;
   end Call_Script;

   function Call_Builtin
     (N    : Node_Access;
      Name : String;
      Info : Builtins.Builtin_Info;
      Env  : Env_Access) return Value
   is
      Count : constant Natural := Natural (Info.Params.Length);
      Given : Node_Array (1 .. Count);
      Args  : Builtins.Arg_Array (1 .. Count);
   begin
      Match_Args (N, Name, Info.Params, Given);
      for I in 1 .. Count loop
         if Given (I) /= null then
            Args (I) := Eval (Given (I), Env);
            if Args (I).Kind = V_None then
               Fail (Given (I), "no value for argument " & Info.Params (I));
            end if;
         elsif I <= Info.Required then
            Fail (N, "missing argument " & Info.Params (I) & " in call to " & Name);
         end if;
      end loop;

      --  Errors in the editor's Ada code become script errors at this call,
      --  with the script's file and line
      begin
         return Info.Func (Args);
      exception
         when Script_Error | Script_Raise | Interrupted | Terminal.Input_Closed =>
            raise;
         when E : Builtins.Builtin_Error =>
            Fail (N, Name & ": " & Ada.Exceptions.Exception_Message (E));
         when Buffers.Read_Only_Error =>
            Fail (N, Name & ": the buffer is read-only");
         when Minibuffer.Not_Interactive =>
            Fail (N, Name & " needs interactive input, which batch mode does not have");
         when E : others =>
            Fail (N, Name & ": " & Ada.Exceptions.Exception_Name (E) & " "
                  & Ada.Exceptions.Exception_Message (E));
      end;
   end Call_Builtin;

   function Call_Editor_Command (N : Node_Access; Name : String; Env : Env_Access) return Value is
      Count : Long_Long_Integer := 1;
   begin
      if Natural (N.List.Length) > 1 then
         Fail (N, "editor command " & Name & " takes at most one argument (a repeat count)");
      elsif Natural (N.List.Length) = 1 then
         declare
            A : constant Node_Access := N.List (1);
         begin
            if A.Kind in N_Named_Arg | N_Range then
               Fail (A, "expected a repeat count");
            end if;
            Count := Eval_Int (A, Env);
            if Count not in 1 .. 1_000_000 then
               Fail (A, "the repeat count must be in 1 .. 1000000");
            end if;
         end;
      end if;

      begin
         Builtins.Run_Editor_Command (Name, Positive (Count), Natural (N.List.Length) = 1);
      exception
         when Script_Error | Script_Raise | Interrupted | Terminal.Input_Closed =>
            raise;
         when Buffers.Read_Only_Error =>
            Fail (N, Name & ": the buffer is read-only");
         when Minibuffer.Not_Interactive =>
            Fail (N, Name & " needs interactive input, which batch mode does not have");
         when E : others =>
            Fail (N, Name & ": " & Ada.Exceptions.Exception_Name (E) & " "
                  & Ada.Exceptions.Exception_Message (E));
      end;
      return None;
   end Call_Editor_Command;

   --  A name with arguments is, in this order: an element of a vector or
   --  string variable, a script subprogram, a builtin, or an editor command
   --  (whose only argument is a repeat count)
   function Call (N : Node_Access; Env : Env_Access) return Value is
      Name : constant String := Strip_Package (To_String (N.Name));
      Info : Builtins.Builtin_Info;
   begin
      if N.Kind = N_Call then
         declare
            Found : Boolean;
            V     : constant Value := Get_Path (N, Env, Name, Found);
         begin
            if Found then
               return Index_Value (N, V, Env);
            end if;
         end;
      end if;

      if Subprograms.Contains (Name) then
         return Call_Script (N, Subprograms.Element (Name), Env);
      elsif Builtins.Find (Name, Info) then
         return Call_Builtin (N, Name, Info, Env);
      elsif Commands.Exists (Name) then
         return Call_Editor_Command (N, Name, Env);
      end if;
      Fail (N, "undefined name " & Name);
   end Call;

   -------------------------------------------------------------------------
   --  Expressions
   -------------------------------------------------------------------------

   function Eval_Name (N : Node_Access; Env : Env_Access) return Value is
      Name  : constant String := Strip_Package (To_String (N.Name));
      Found : Boolean;
      V     : constant Value := Get_Path (N, Env, Name, Found);
   begin
      --  Not a variable: True, False, a few ASCII names, or a call without
      --  arguments
      if Found then
         return V;
      elsif Name = "true" then
         return Make_Bool (True);
      elsif Name = "false" then
         return Make_Bool (False);
      elsif Name = "lf" then
         return Make_Char (L1.LF);
      elsif Name = "cr" then
         return Make_Char (L1.CR);
      elsif Name = "ht" then
         return Make_Char (L1.HT);
      elsif Name = "nul" then
         return Make_Char (L1.NUL);
      end if;
      return Call (N, Env);
   end Eval_Name;

   function Eval_Unary (N : Node_Access; Env : Env_Access) return Value is
      V : constant Value := Eval (N.Left, Env);
   begin
      if N.Op = K_Not then
         if V.Kind /= V_Boolean then
            Fail (N, "'not' needs a Boolean, not " & Kind_Name (V));
         end if;
         return Make_Bool (not V.Bool);
      end if;
      if V.Kind /= V_Integer then
         Fail (N, "'" & Image (N.Op) & "' needs an Integer, not " & Kind_Name (V));
      end if;
      case N.Op is
         when T_Minus => return Make_Int (-V.Int);
         when K_Abs   => return Make_Int (abs V.Int);
         when others  => return V;
      end case;
   exception
      when Constraint_Error =>
         Fail (N, "integer overflow");
   end Eval_Unary;

   function Eval_Binary (N : Node_Access; Env : Env_Access) return Value is
   begin
      if N.Flag then
         declare
            L : constant Boolean := Eval_Bool (N.Left, Env);
         begin
            if N.Op = K_And then
               return Make_Bool (L and then Eval_Bool (N.Right, Env));
            else
               return Make_Bool (L or else Eval_Bool (N.Right, Env));
            end if;
         end;
      end if;

      declare
         L  : constant Value := Eval (N.Left, Env);
         R  : constant Value := Eval (N.Right, Env);
         Op : constant String := "'" & Image (N.Op) & "'";
      begin
         case N.Op is
            when T_Plus | T_Minus | T_Star | T_Slash | K_Mod | K_Rem | T_Power =>
               if L.Kind /= V_Integer or else R.Kind /= V_Integer then
                  Fail (N, Op & " needs Integer operands, not " & Kind_Name (L)
                        & " and " & Kind_Name (R));
               elsif N.Op in T_Slash | K_Mod | K_Rem and then R.Int = 0 then
                  Fail (N, "division by zero");
               elsif N.Op = T_Power and then R.Int < 0 then
                  Fail (N, "negative exponent");
               end if;
               begin
                  case N.Op is
                     when T_Plus  => return Make_Int (L.Int + R.Int);
                     when T_Minus => return Make_Int (L.Int - R.Int);
                     when T_Star  => return Make_Int (L.Int * R.Int);
                     when T_Slash => return Make_Int (L.Int / R.Int);
                     when K_Mod   => return Make_Int (L.Int mod R.Int);
                     when K_Rem   => return Make_Int (L.Int rem R.Int);
                     when others =>
                        --  Don't spend time on a power that must overflow
                        if R.Int > 64 and then abs L.Int > 1 then
                           raise Constraint_Error;
                        end if;
                        return Make_Int (L.Int ** Natural (R.Int));
                  end case;
               exception
                  when Constraint_Error =>
                     Fail (N, "integer overflow");
               end;

            when T_Ampersand =>
               --  With vectors, & joins them or adds an element at either end
               if L.Kind = V_Vector or else R.Kind = V_Vector then
                  if L.Kind = V_None or else R.Kind = V_None then
                     Fail (N, "'&' needs two values");
                  end if;
                  declare
                     Result : Value := (if L.Kind = V_Vector then L else Make_Vector);
                  begin
                     if L.Kind /= V_Vector then
                        Append (Result, L);
                     end if;
                     if R.Kind = V_Vector then
                        for I in 1 .. Item_Count (R) loop
                           Append (Result, Element (R, I));
                        end loop;
                     else
                        Append (Result, R);
                     end if;
                     return Result;
                  end;
               end if;
               if L.Kind not in V_String | V_Character
                 or else R.Kind not in V_String | V_Character
               then
                  Fail (N, "'&' needs String or Character operands, not "
                        & Kind_Name (L) & " and " & Kind_Name (R));
               end if;
               return Make_Str (To_Display (L) & To_Display (R));

            when T_Eq | T_Ne =>
               if L.Kind in V_Vector | V_Record or else R.Kind in V_Vector | V_Record then
                  return Make_Bool (Equal (L, R) = (N.Op = T_Eq));
               end if;
               return Make_Bool ((Compare (N, L, R) = 0) = (N.Op = T_Eq));
            when T_Lt => return Make_Bool (Compare (N, L, R) < 0);
            when T_Le => return Make_Bool (Compare (N, L, R) <= 0);
            when T_Gt => return Make_Bool (Compare (N, L, R) > 0);
            when T_Ge => return Make_Bool (Compare (N, L, R) >= 0);

            when K_And | K_Or | K_Xor =>
               if L.Kind /= V_Boolean or else R.Kind /= V_Boolean then
                  Fail (N, Op & " needs Boolean operands, not " & Kind_Name (L)
                        & " and " & Kind_Name (R));
               end if;
               return Make_Bool
                 (case N.Op is
                     when K_And  => L.Bool and R.Bool,
                     when K_Or   => L.Bool or R.Bool,
                     when others => L.Bool xor R.Bool);

            when others =>
               Fail (N, "unknown operator " & Op);
         end case;
      end;
   end Eval_Binary;

   function Eval_Attribute (N : Node_Access; Env : Env_Access) return Value is
      Attr    : constant String := To_String (N.Name);
      Prefix  : constant Node_Access := N.Left;
      Argc    : constant Natural := Natural (N.List.Length);
      Is_Type : Boolean := False;
      T       : Type_Name := T_Any;

      procedure Need (Count : Natural) is
      begin
         if Argc /= Count then
            Fail (N, "'" & Attr & " takes " & Utils.Img (Count)
                  & (if Count = 1 then " argument" else " arguments"));
         end if;
      end Need;

      function Arg (I : Positive) return Value is
      begin
         if N.List (I).Kind in N_Named_Arg | N_Range then
            Fail (N.List (I), "unexpected argument");
         end if;
         return Eval (N.List (I), Env);
      end Arg;

      function Integer_Type return Boolean is (T in T_Integer | T_Natural | T_Positive);

   begin
      if Prefix.Kind = N_Name then
         declare
            Found : Boolean;
         begin
            --  A type name, as in Integer'Image, unless a variable has that name
            T := Type_Of_Name (To_String (Prefix.Name), Found);
            Is_Type := Found and then not Var_Exists (Env, To_String (Prefix.Name));
         end;
      end if;

      if not Is_Type then
         Need (0);
         declare
            V : constant Value := Eval (Prefix, Env);
         begin
            if Attr = "length" or else Attr = "last" then
               if V.Kind = V_Vector then
                  return Make_Int (Long_Long_Integer (Item_Count (V)));
               elsif V.Kind /= V_String then
                  Fail (N, "'" & Attr & " needs a String or a Vector, not " & Kind_Name (V));
               end if;
               return Make_Int (Long_Long_Integer (Length (V.Str)));
            elsif Attr = "first" then
               if V.Kind not in V_String | V_Vector then
                  Fail (N, "'First needs a String or a Vector, not " & Kind_Name (V));
               end if;
               return Make_Int (1);
            elsif Attr = "image" then
               if V.Kind = V_None then
                  Fail (N, "'Image needs a value");
               end if;
               return Make_Str (Ada_Image (V));
            end if;
            Fail (N, "unknown attribute '" & Attr);
         end;
      end if;

      --  Attributes of types, e.g. Integer'Image (X)
      if Attr = "image" then
         Need (1);
         declare
            V : constant Value := Arg (1);
         begin
            if not Accepts ((if Integer_Type then T_Integer else T), V) then
               Fail (N, Type_Image (T) & "'Image needs " & Type_Image (T) & ", not "
                     & Kind_Name (V));
            end if;
            return Make_Str (Ada_Image (V));
         end;

      elsif Attr = "value" then
         Need (1);
         declare
            V : constant Value := Arg (1);
         begin
            if V.Kind /= V_String then
               Fail (N, "'Value needs a String, not " & Kind_Name (V));
            end if;
            declare
               Text : constant String :=
                 Ada.Strings.Fixed.Trim (To_String (V.Str), Ada.Strings.Both);
            begin
               if Integer_Type then
                  declare
                     R : Value;
                  begin
                     R := Make_Int (Long_Long_Integer'Value (Text));
                     Check_Type (N, T, R, Type_Image (T) & "'Value");
                     return R;
                  exception
                     when Constraint_Error =>
                        Fail (N, "not a valid " & Type_Image (T) & ": """ & Text & """");
                  end;
               elsif T = T_Boolean then
                  declare
                     Lower : String := Text;
                  begin
                     for C of Lower loop
                        C := Utils.To_Lower (C);
                     end loop;
                     if Lower = "true" then
                        return Make_Bool (True);
                     elsif Lower = "false" then
                        return Make_Bool (False);
                     end if;
                     Fail (N, "not a valid Boolean: """ & Text & """");
                  end;
               end if;
               Fail (N, "'Value is not available for " & Type_Image (T));
            end;
         end;

      elsif Attr = "val" then
         Need (1);
         declare
            V : constant Value := Arg (1);
         begin
            if V.Kind /= V_Integer then
               Fail (N, "'Val needs an Integer, not " & Kind_Name (V));
            elsif T = T_Character then
               if V.Int not in 0 .. 255 then
                  Fail (N, "Character'Val argument out of range 0 .. 255");
               end if;
               return Make_Char (Character'Val (V.Int));
            elsif T = T_Boolean then
               if V.Int not in 0 .. 1 then
                  Fail (N, "Boolean'Val argument out of range 0 .. 1");
               end if;
               return Make_Bool (V.Int = 1);
            end if;
            Fail (N, "'Val is not available for " & Type_Image (T));
         end;

      elsif Attr = "pos" then
         Need (1);
         declare
            V : constant Value := Arg (1);
         begin
            if T = T_Character and then V.Kind = V_Character then
               return Make_Int (Long_Long_Integer (Character'Pos (V.Char)));
            elsif T = T_Boolean and then V.Kind = V_Boolean then
               return Make_Int (if V.Bool then 1 else 0);
            end if;
            Fail (N, Type_Image (T) & "'Pos needs " & Type_Image (T) & ", not " & Kind_Name (V));
         end;

      elsif Attr = "min" or else Attr = "max" then
         Need (2);
         declare
            A : constant Value := Arg (1);
            B : constant Value := Arg (2);
         begin
            if not Accepts ((if Integer_Type then T_Integer else T), A) then
               Fail (N, "'" & Attr & " needs " & Type_Image (T) & " arguments");
            end if;
            if (Compare (N, A, B) <= 0) = (Attr = "min") then
               return A;
            else
               return B;
            end if;
         end;

      elsif Attr = "first" or else Attr = "last" then
         Need (0);
         declare
            First : constant Boolean := Attr = "first";
         begin
            case T is
               when T_Integer =>
                  return Make_Int (if First then Long_Long_Integer'First else Long_Long_Integer'Last);
               when T_Natural =>
                  return Make_Int (if First then 0 else Long_Long_Integer'Last);
               when T_Positive =>
                  return Make_Int (if First then 1 else Long_Long_Integer'Last);
               when T_Character =>
                  return Make_Char (if First then Character'First else Character'Last);
               when T_Boolean =>
                  return Make_Bool (not First);
               when others =>
                  Fail (N, "'" & Attr & " is not available for " & Type_Image (T));
            end case;
         end;

      elsif Attr = "succ" or else Attr = "pred" then
         Need (1);
         declare
            V     : constant Value := Arg (1);
            Delta_Value : constant Integer := (if Attr = "succ" then 1 else -1);
         begin
            if Integer_Type and then V.Kind = V_Integer then
               declare
                  R : constant Value := Make_Int (V.Int + Long_Long_Integer (Delta_Value));
               begin
                  Check_Type (N, T, R, Type_Image (T) & "'" & Attr);
                  return R;
               end;
            elsif T = T_Character and then V.Kind = V_Character then
               if Character'Pos (V.Char) + Delta_Value not in 0 .. 255 then
                  Fail (N, "Character'" & Attr & " out of range");
               end if;
               return Make_Char (Character'Val (Character'Pos (V.Char) + Delta_Value));
            end if;
            Fail (N, "'" & Attr & " needs " & Type_Image (T) & ", not " & Kind_Name (V));
         end;
      end if;

      Fail (N, "unknown attribute '" & Attr & " for " & Type_Image (T));
   end Eval_Attribute;

   function Eval (N : Node_Access; Env : Env_Access) return Value is
   begin
      case N.Kind is
         when N_Integer   => return Make_Int (N.Int);
         when N_String    => return Make_Str (To_String (N.Name));
         when N_Character => return Make_Char (Character'Val (N.Int));
         when N_Name      => return Eval_Name (N, Env);
         when N_Call      => return Call (N, Env);
         when N_Unary     => return Eval_Unary (N, Env);
         when N_Binary    => return Eval_Binary (N, Env);
         when N_Attribute => return Eval_Attribute (N, Env);
         when N_Index     => return Index_Value (N, Eval (N.Left, Env), Env);

         when N_Selected =>
            declare
               R : constant Value := Eval (N.Left, Env);
               I : Natural;
            begin
               if R.Kind /= V_Record then
                  Fail (N, "." & To_String (N.Name) & " needs a record, not " & Kind_Name (R));
               end if;
               I := Find_Field (R, To_String (N.Name));
               if I = 0 then
                  Fail (N, "the record has no field " & To_String (N.Name));
               end if;
               return Element (R, I);
            end;

         when N_Vector_Aggregate =>
            declare
               R : Value := Make_Vector;
            begin
               for E of N.List loop
                  declare
                     X : constant Value := Eval (E, Env);
                  begin
                     if X.Kind = V_None then
                        Fail (E, "this does not produce a value");
                     end if;
                     Append (R, X);
                  end;
               end loop;
               return R;
            end;

         when N_Record_Aggregate =>
            declare
               R : Value := Make_Record;
            begin
               for A of N.List loop
                  if Find_Field (R, To_String (A.Name)) > 0 then
                     Fail (A, "field " & To_String (A.Name) & " is given twice");
                  end if;
                  declare
                     X : constant Value := Eval (A.Left, Env);
                  begin
                     if X.Kind = V_None then
                        Fail (A.Left, "this does not produce a value");
                     end if;
                     Set_Field (R, To_String (A.Name), X);
                  end;
               end loop;
               return R;
            end;

         when N_If_Expr =>
            for W of N.List loop
               if Eval_Bool (W.Left, Env) then
                  return Eval (W.Right, Env);
               end if;
            end loop;
            return Eval (N.Extra, Env);

         when N_Membership =>
            declare
               V      : constant Value := Eval (N.Left, Env);
               Lo     : constant Value := Eval (N.Right, Env);
               Hi     : constant Value := Eval (N.Extra, Env);
               Inside : constant Boolean :=
                 Compare (N, Lo, V) <= 0 and then Compare (N, V, Hi) <= 0;
            begin
               return Make_Bool (Inside /= N.Flag);
            end;

         when others =>
            Fail (N, "expected an expression");
      end case;
   end Eval;

   -------------------------------------------------------------------------
   --  Statements
   -------------------------------------------------------------------------

   function Choice_Matches (C : Node_Access; Selector : Value; Env : Env_Access) return Boolean is
   begin
      case C.Kind is
         when N_Others =>
            return True;
         when N_Range =>
            return Compare (C, Eval (C.Left, Env), Selector) <= 0
              and then Compare (C, Selector, Eval (C.Right, Env)) <= 0;
         when others =>
            return Compare (C, Eval (C, Env), Selector) = 0;
      end case;
   end Choice_Matches;

   -------------------------------------------------------------------------
   --  Assignment to variables, elements and fields
   -------------------------------------------------------------------------

   procedure Set_Path (N : Node_Access; Container : in out Value; Path : String; Item : Value) is
      Dot   : constant Natural := Ada.Strings.Fixed.Index (Path, ".");
      Field : constant String := (if Dot = 0 then Path else Path (Path'First .. Dot - 1));
   begin
      if Container.Kind /= V_Record then
         Fail (N, "cannot set field " & Field & " of a " & Kind_Name (Container));
      end if;
      if Dot = 0 then
         Set_Field (Container, Field, Item);
      else
         declare
            I     : constant Natural := Find_Field (Container, Field);
            Child : Value;
         begin
            if I = 0 then
               Fail (N, "the record has no field " & Field);
            end if;
            Child := Element (Container, I);
            Set_Path (N, Child, Path (Dot + 1 .. Path'Last), Item);
            Set_Field (Container, Field, Child);
         end;
      end if;
   end Set_Path;

   procedure Assign_Target (Env : Env_Access; Target : Node_Access; V : Value) is
   begin
      case Target.Kind is
         when N_Name =>
            declare
               Name : constant String := To_String (Target.Name);
               Dot  : constant Natural := Ada.Strings.Fixed.Index (Name, ".");
            begin
               if Dot = 0 or else Var_Exists (Env, Name) then
                  Assign (Env, Target, Name, V);
                  return;
               end if;
               declare
                  Root_Name : constant String := Name (Name'First .. Dot - 1);
                  Found     : Boolean;
                  Root      : Value := Get_Var (Env, Root_Name, Found);
               begin
                  if not Found then
                     Fail (Target, "undefined variable " & Root_Name);
                  end if;
                  Set_Path (Target, Root, Name (Dot + 1 .. Name'Last), V);
                  Assign (Env, Target, Root_Name, Root);
               end;
            end;

         --  Values are copies: change the element in a copy of the container,
         --  then assign the whole container back to where it came from
         when N_Call | N_Index =>
            declare
               Found     : Boolean := True;
               Container : Value;
               Index     : Long_Long_Integer;
            begin
               if Target.Kind = N_Call then
                  Container := Get_Path (Target, Env, To_String (Target.Name), Found);
               else
                  Container := Eval (Target.Left, Env);
               end if;
               if not Found then
                  Fail (Target, "undefined variable " & To_String (Target.Name));
               elsif Natural (Target.List.Length) /= 1
                 or else Target.List (1).Kind in N_Range | N_Named_Arg
               then
                  Fail (Target, "an element assignment needs exactly one index");
               end if;
               Index := Eval_Int (Target.List (1), Env);

               case Container.Kind is
                  when V_Vector =>
                     if Index < 1 or else Index > Long_Long_Integer (Item_Count (Container)) then
                        Fail (Target.List (1), "index" & Long_Long_Integer'Image (Index)
                              & " is outside 1 .." & Natural'Image (Item_Count (Container)));
                     end if;
                     Replace_Element (Container, Positive (Index), V);
                  when V_String =>
                     if V.Kind /= V_Character then
                        Fail (Target, "a string element must be a Character, not " & Kind_Name (V));
                     elsif Index < 1 or else Index > Long_Long_Integer (Length (Container.Str)) then
                        Fail (Target.List (1), "index" & Long_Long_Integer'Image (Index)
                              & " is outside 1 .." & Natural'Image (Length (Container.Str)));
                     end if;
                     declare
                        S : Unbounded_String := Container.Str;
                     begin
                        Replace_Element (S, Positive (Index), V.Char);
                        Container := (Kind => V_String, Str => S);
                     end;
                  when others =>
                     Fail (Target, "a " & Kind_Name (Container) & " cannot be indexed");
               end case;

               if Target.Kind = N_Call then
                  declare
                     Name_Node : aliased Node :=
                       (Kind   => N_Name,
                        File   => Target.File,
                        Line   => Target.Line,
                        Col    => Target.Col,
                        Name   => Target.Name,
                        others => <>);
                  begin
                     Assign_Target (Env, Name_Node'Unchecked_Access, Container);
                  end;
               else
                  Assign_Target (Env, Target.Left, Container);
               end if;
            end;

         when N_Selected =>
            declare
               Container : Value := Eval (Target.Left, Env);
            begin
               if Container.Kind /= V_Record then
                  Fail (Target, "." & To_String (Target.Name) & " needs a record, not "
                        & Kind_Name (Container));
               end if;
               Set_Field (Container, To_String (Target.Name), V);
               Assign_Target (Env, Target.Left, Container);
            end;

         when others =>
            Fail (Target, "this cannot be assigned to");
      end case;
   end Assign_Target;

   --  Append (V, X), Prepend (V, X) and Delete (V, Index [, Count]) change
   --  the variable (or element, or field) given as the first argument
   function Run_Intrinsic (N : Node_Access; Env : Env_Access) return Boolean is
      Name : constant String := To_String (N.Name);
      Argc : constant Natural := Natural (N.List.Length);
   begin
      if (Name /= "append" and then Name /= "prepend" and then Name /= "delete")
        or else Subprograms.Contains (Name)
      then
         return False;
      end if;
      if Argc < 2 or else Argc > (if Name = "delete" then 3 else 2) then
         Fail (N, (if Name = "delete" then "Delete needs a vector, an index and optionally a count"
                   else Name & " needs a container and an item"));
      end if;

      declare
         Target    : constant Node_Access := N.List (1);
         Container : Value;
         Item      : Value;
      begin
         if Target.Kind not in N_Name | N_Call | N_Index | N_Selected then
            Fail (Target, "the first argument of " & Name & " must be a variable");
         end if;
         Container := Eval (Target, Env);
         Item := Eval (N.List (2), Env);
         if Item.Kind = V_None then
            Fail (N.List (2), "this does not produce a value");
         end if;

         case Container.Kind is
            when V_Vector =>
               if Name = "append" then
                  Append (Container, Item);
               elsif Name = "prepend" then
                  Prepend (Container, Item);
               else
                  declare
                     Count : constant Long_Long_Integer :=
                       (if Argc = 3 then Eval_Int (N.List (3), Env) else 1);
                  begin
                     if Item.Kind /= V_Integer then
                        Fail (N.List (2), "the index must be an Integer");
                     elsif Count < 1 or else Item.Int < 1
                       or else Item.Int + Count - 1 > Long_Long_Integer (Item_Count (Container))
                     then
                        Fail (N, "cannot delete" & Long_Long_Integer'Image (Count)
                              & " element(s) at" & Long_Long_Integer'Image (Item.Int)
                              & " from a vector of" & Natural'Image (Item_Count (Container)));
                     end if;
                     Delete (Container, Positive (Item.Int), Positive (Count));
                  end;
               end if;
            when V_String =>
               if Name = "delete" or else Item.Kind not in V_String | V_Character then
                  Fail (N, Name & " on a String needs a String or Character item");
               end if;
               Container := Make_Str (if Name = "append" then To_Display (Container) & To_Display (Item)
                                      else To_Display (Item) & To_Display (Container));
            when others =>
               Fail (Target, Name & " needs a Vector or a String, not " & Kind_Name (Container));
         end case;
         Assign_Target (Env, Target, Container);
      end;
      return True;
   end Run_Intrinsic;

   --  The loop variable is a constant that exists only in the loop; a
   --  variable with the same name comes back afterwards
   function Exec_For_Of (S : Node_Access; Env : Env_Access) return Flow is
      Name      : constant String := To_String (S.Name);
      Container : constant Value := Eval (S.Left, Env);
      Had       : constant Boolean := Env.Contains (Name);
      Old       : constant Variable :=
        (if Had then Env.Element (Name) else (Val => None, others => <>));
      Count     : Natural := 0;
      F         : Flow := Normal;
   begin
      case Container.Kind is
         when V_Vector => Count := Item_Count (Container);
         when V_String => Count := Length (Container.Str);
         when others =>
            Fail (S.Left, "for ... of needs a Vector or a String, not " & Kind_Name (Container));
      end case;
      for I in 1 .. Count loop
         Env.Include (Name, (Val         => (if Container.Kind = V_Vector
                                             then Element (Container, I)
                                             else Make_Char (Element (Container.Str, I))),
                             Decl_Type   => T_Any,
                             Is_Constant => True));
         F := Exec_List (S.Stmts, Env);
         exit when F /= Normal;
      end loop;
      if Had then
         Env.Include (Name, Old);
      else
         Env.Exclude (Name);
      end if;
      return (if F = Return_From then Return_From else Normal);
   end Exec_For_Of;

   -------------------------------------------------------------------------
   --  Exceptions
   -------------------------------------------------------------------------

   function Run_Handler (W : Node_Access; Name, Message : String; Env : Env_Access) return Flow is
      Result : Flow;
   begin
      if Length (W.Name) > 0 then
         Env.Include (To_String (W.Name),
                      (Val => Make_Str (Message), Decl_Type => T_String, Is_Constant => True));
      end if;
      Handling.Append ((To_Unbounded_String (Name), To_Unbounded_String (Message)));
      begin
         Result := Exec_List (W.Stmts, Env);
      exception
         when others =>
            Handling.Delete_Last;
            raise;
      end;
      Handling.Delete_Last;
      return Result;
   end Run_Handler;

   function Exec_Guarded
     (Stmts, Handlers : Node_Vectors.Vector; Env : Env_Access) return Flow
   is
      use type Ada.Exceptions.Exception_Id;
   begin
      if Handlers.Is_Empty then
         return Exec_List (Stmts, Env);
      end if;
      return Exec_List (Stmts, Env);
   exception
      when E : Script_Raise | Script_Error =>
         declare
            --  Run-time errors can be handled too, as the exception Script_Error
            Is_Error : constant Boolean := Ada.Exceptions.Exception_Identity (E) = Script_Error'Identity;
            Name     : constant String := (if Is_Error then "script_error" else To_String (Raised_Name));
            Message  : constant String :=
              (if Is_Error then Ada.Exceptions.Exception_Message (E) else To_String (Raised_Message));
         begin
            for W of Handlers loop
               for C of W.List loop
                  if C.Kind = N_Others or else Strip_Package (To_String (C.Name)) = Name then
                     return Run_Handler (W, Name, Message, Env);
                  end if;
               end loop;
            end loop;
            raise;
         end;
   end Exec_Guarded;

   procedure Raise_Unhandled with No_Return;

   procedure Raise_Unhandled is
   begin
      raise Script_Error with
        To_String (Raised_Where) & ": unhandled exception " & To_String (Raised_Name)
        & (if Length (Raised_Message) > 0 then ": " & To_String (Raised_Message) else "");
   end Raise_Unhandled;

   function Current_Exception_Name return String is
     (if Handling.Is_Empty then "" else To_String (Handling.Last_Element.Name));

   function Current_Exception_Message return String is
     (if Handling.Is_Empty then "" else To_String (Handling.Last_Element.Message));

   procedure Make_Command (Where : Node_Access; Sub : Node_Access) is
      Name : constant String := To_String (Sub.Name);
   begin
      if Sub.Flag then
         Fail (Where, Name & " is a function; only procedures can be commands");
      end if;
      for P of Sub.List loop
         if P.Left = null then
            Fail (Where, "command " & Name & " cannot have parameters without defaults");
         end if;
      end loop;
      Sub.Int := 1;
      Commands.Register_Script (Name);
   end Make_Command;

   function Exec (S : Node_Access; Env : Env_Access) return Flow is
   begin
      --  Every 2000 statements, see whether the user pressed C-g
      Steps := Steps + 1;
      if Steps >= 2_000 then
         Steps := 0;
         if Interrupt_Check /= null and then Interrupt_Check.all then
            raise Interrupted with Where (S) & ": Quit";
         end if;
      end if;

      case S.Kind is
         when N_Null =>
            return Normal;

         when N_Declare =>
            declare
               Name : constant String := To_String (S.Name);
               V    : Value := None;
            begin
               if S.Left /= null then
                  V := Eval (S.Left, Env);
                  if V.Kind = V_None then
                     Fail (S.Left, "the initial value of " & Name & " is not a value");
                  end if;
                  Check_Type (S, S.Decl_Type, V, Name);
               elsif S.Decl_Type = T_Vector then
                  V := Make_Vector;
               end if;
               Env.Include (Name, (Val => V, Decl_Type => S.Decl_Type, Is_Constant => S.Flag));
               return Normal;
            end;

         when N_Assign =>
            declare
               V : constant Value := Eval (S.Left, Env);
            begin
               if V.Kind = V_None then
                  Fail (S.Left, "the expression does not produce a value");
               end if;
               Assign_Target (Env, (if S.Extra = null then S else S.Extra), V);
               return Normal;
            end;

         when N_Exception_Decl =>
            return Normal;

         when N_Raise =>
            --  "raise;" raises the exception being handled again
            if Length (S.Name) = 0 then
               if Handling.Is_Empty then
                  Fail (S, "raise; is only allowed in an exception handler");
               end if;
               Raised_Name := Handling.Last_Element.Name;
               Raised_Message := Handling.Last_Element.Message;
               if To_String (Raised_Name) = "script_error" then
                  raise Script_Error with To_String (Raised_Message);
               end if;
            else
               Raised_Name := To_Unbounded_String (Strip_Package (To_String (S.Name)));
               Raised_Message :=
                 (if S.Left = null then Null_Unbounded_String
                  else To_Unbounded_String (To_Display (Eval (S.Left, Env))));
               if To_String (Raised_Name) = "script_error" then
                  raise Script_Error with Where (S) & ": " & To_String (Raised_Message);
               end if;
            end if;
            Raised_Where := To_Unbounded_String (Where (S));
            raise Script_Raise;

         when N_Call_Stmt =>
            if S.Left.Kind = N_Call and then Run_Intrinsic (S.Left, Env) then
               return Normal;
            end if;
            if S.Left.Kind = N_Name
              and then Var_Exists (Env, Strip_Package (To_String (S.Left.Name)))
            then
               Fail (S, To_String (S.Left.Name) & " is a variable, not a procedure");
            end if;
            declare
               Ignored : constant Value := Call (S.Left, Env);
               pragma Unreferenced (Ignored);
            begin
               return Normal;
            end;

         when N_If =>
            for W of S.List loop
               if Eval_Bool (W.Left, Env) then
                  return Exec_List (W.Stmts, Env);
               end if;
            end loop;
            return Exec_List (S.Else_Stmts, Env);

         when N_Case =>
            declare
               Selector : constant Value := Eval (S.Left, Env);
            begin
               if Selector.Kind = V_None then
                  Fail (S.Left, "the case selector has no value");
               end if;
               for W of S.List loop
                  for C of W.List loop
                     if Choice_Matches (C, Selector, Env) then
                        return Exec_List (W.Stmts, Env);
                     end if;
                  end loop;
               end loop;
               Fail (S, "no case alternative for " & Literal_Image (Selector));
            end;

         when N_While =>
            while Eval_Bool (S.Left, Env) loop
               case Exec_List (S.Stmts, Env) is
                  when Normal      => null;
                  when Exit_Loop   => exit;
                  when Return_From => return Return_From;
               end case;
            end loop;
            return Normal;

         when N_Loop =>
            loop
               case Exec_List (S.Stmts, Env) is
                  when Normal      => null;
                  when Exit_Loop   => exit;
                  when Return_From => return Return_From;
               end case;
            end loop;
            return Normal;

         when N_For =>
            if S.Int = 1 then
               return Exec_For_Of (S, Env);
            end if;
            declare
               Name : constant String := To_String (S.Name);
               Lo   : constant Long_Long_Integer := Eval_Int (S.Left, Env);
               Hi   : constant Long_Long_Integer := Eval_Int (S.Right, Env);
               Had  : constant Boolean := Env.Contains (Name);
               Old  : constant Variable :=
                 (if Had then Env.Element (Name) else (Val => None, others => <>));
               I    : Long_Long_Integer := (if S.Flag then Hi else Lo);
               F    : Flow := Normal;
            begin
               if Lo <= Hi then
                  loop
                     Env.Include (Name, (Val         => Make_Int (I),
                                         Decl_Type   => T_Integer,
                                         Is_Constant => True));
                     F := Exec_List (S.Stmts, Env);
                     exit when F /= Normal;
                     exit when (if S.Flag then I = Lo else I = Hi);
                     I := (if S.Flag then I - 1 else I + 1);
                  end loop;
               end if;
               if Had then
                  Env.Include (Name, Old);
               else
                  Env.Exclude (Name);
               end if;
               return (if F = Return_From then Return_From else Normal);
            end;

         when N_Exit =>
            if S.Left = null or else Eval_Bool (S.Left, Env) then
               return Exit_Loop;
            end if;
            return Normal;

         when N_Return =>
            Return_Value := (if S.Left = null then None else Eval (S.Left, Env));
            return Return_From;

         when N_Block =>
            return Exec_Guarded (S.Stmts, S.Else_Stmts, Env);

         --  A subprogram is defined when its body is reached, so loading a
         --  script again replaces its subprograms
         when N_Subprogram =>
            Subprograms.Include (To_String (S.Name), S);
            if S.Int = 1 then
               Make_Command (S, S);
            end if;
            return Normal;

         when N_Pragma =>
            if To_String (S.Name) /= "command" then
               Fail (S, "unknown pragma " & To_String (S.Name));
            elsif Natural (S.List.Length) /= 1 or else S.List (1).Kind /= N_Name then
               Fail (S, "pragma Command needs the name of a procedure");
            end if;
            declare
               Name : constant String := To_String (S.List (1).Name);
            begin
               if not Subprograms.Contains (Name) then
                  Fail (S, "pragma Command: there is no procedure named " & Name);
               end if;
               Make_Command (S, Subprograms.Element (Name));
            end;
            return Normal;

         when others =>
            Fail (S, "expected a statement");
      end case;
   end Exec;

   function Exec_List (List : Node_Vectors.Vector; Env : Env_Access) return Flow is
   begin
      for S of List loop
         declare
            F : constant Flow := Exec (S, Env);
         begin
            if F /= Normal then
               return F;
            end if;
         end;
      end loop;
      return Normal;
   end Exec_List;

   -------------------------------------------------------------------------
   --  Entry points
   -------------------------------------------------------------------------

   procedure Execute_Source (Source : String; File_Name : String) is
      Program : constant Node_Vectors.Vector := Parser.Parse (Source, File_Name);
   begin
      declare
         Result : constant Flow := Exec_List (Program, Global_Env);
         pragma Unreferenced (Result);  --  A top-level return just ends the script
      begin
         null;
      end;
   exception
      when Script_Raise =>
         Raise_Unhandled;
      when E : Interrupted =>
         raise Script_Error with Ada.Exceptions.Exception_Message (E);
   end Execute_Source;

   procedure Load_File (File_Name : String; Display_Name : String := "") is
      use Ada.Streams.Stream_IO;
      Shown : constant String := (if Display_Name = "" then File_Name else Display_Name);
      F     : File_Type;
   begin
      if not Ada.Directories.Exists (File_Name) then
         raise Script_Error with Shown & ": no such file";
      end if;
      Open (F, In_File, File_Name);
      declare
         Text : String (1 .. Natural (Ada.Directories.Size (File_Name)));
      begin
         String'Read (Stream (F), Text);
         Close (F);
         Execute_Source (Text, Shown);
      end;
   exception
      when Script_Error | Terminal.Input_Closed =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
      when E : others =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise Script_Error with Shown & ": " & Ada.Exceptions.Exception_Message (E);
   end Load_File;

   function Evaluate (Source : String; File_Name : String := "eval") return String is
      Text : constant String := Ada.Strings.Fixed.Trim (Source, Ada.Strings.Both);
   begin
      if Text = "" then
         return "";
      elsif Text (Text'Last) = ';' then
         Execute_Source (Text, File_Name);
         return "";
      end if;
      return Literal_Image (Eval (Parser.Parse_Expression (Text, File_Name), Global_Env));
   exception
      when Script_Raise =>
         Raise_Unhandled;
      when E : Interrupted =>
         raise Script_Error with Ada.Exceptions.Exception_Message (E);
   end Evaluate;

   procedure Run_Command (Name : String) is
   begin
      if not Subprograms.Contains (Name) then
         raise Script_Error with "command " & Name & " is no longer defined";
      end if;
      declare
         Sub       : constant Node_Access := Subprograms.Element (Name);
         Call_Node : aliased Node :=
           (Kind   => N_Call,
            File   => Sub.File,
            Line   => Sub.Line,
            Col    => Sub.Col,
            Name   => Sub.Name,
            others => <>);
         Ignored   : constant Value :=
           Call_Script (Call_Node'Unchecked_Access, Sub, Global_Env);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   exception
      when Script_Raise =>
         Raise_Unhandled;
      when E : Interrupted =>
         raise Script_Error with Ada.Exceptions.Exception_Message (E);
   end Run_Command;

   function Is_Defined (Name : String) return Boolean is (Subprograms.Contains (Name));

end Scripts.Interpreter;
