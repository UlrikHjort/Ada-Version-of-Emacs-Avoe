-- ***************************************************************************
--                           Avoe - Scripts.Parser
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

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Scripts.Lexer;         use Scripts.Lexer;
with Scripts.Values;        use Scripts.Values;
with Utils;

package body Scripts.Parser is

   type State is record
      Tokens     : Token_Vectors.Vector;
      Pos        : Positive := 1;
      File       : Natural := 0;
      File_Name  : Unbounded_String;
      Loop_Depth : Natural := 0;
      Nesting    : Natural := 0;  --  Guards the parser and interpreter stacks
   end record;

   Max_Nesting : constant := 1000;

   -------------------------------------------------------------------------
   --  Token access and errors
   -------------------------------------------------------------------------

   function Cur (S : State) return Token is (S.Tokens (S.Pos));
   function Kind (S : State) return Token_Kind is (S.Tokens (S.Pos).Kind);
   function Next_Kind (S : State) return Token_Kind is
     (if S.Pos < S.Tokens.Last_Index then S.Tokens (S.Pos + 1).Kind else T_EOF);
   function Kind_At (S : State; Offset : Natural) return Token_Kind is
     (if S.Pos + Offset <= S.Tokens.Last_Index then S.Tokens (S.Pos + Offset).Kind else T_EOF);

   procedure Advance (S : in out State) is
   begin
      if S.Pos < S.Tokens.Last_Index then
         S.Pos := S.Pos + 1;
      end if;
   end Advance;

   function Describe (T : Token) return String is
     (case T.Kind is
         when T_Identifier => "'" & To_String (T.Text) & "'",
         when T_Integer    => "an integer",
         when T_String     => "a string",
         when T_Character  => "a character",
         when T_EOF        => "end of input",
         when others       => "'" & Image (T.Kind) & "'");

   procedure Error_At (S : State; T : Token; Msg : String) with No_Return;

   procedure Error_At (S : State; T : Token; Msg : String) is
   begin
      raise Script_Error with
        To_String (S.File_Name) & ":" & Utils.Img (T.Line) & ":"
        & Utils.Img (T.Col) & ": " & Msg;
   end Error_At;

   procedure Error (S : State; Msg : String) with No_Return;

   procedure Error (S : State; Msg : String) is
   begin
      Error_At (S, Cur (S), Msg);
   end Error;

   procedure Nest (S : in out State) is
   begin
      S.Nesting := S.Nesting + 1;
      if S.Nesting > Max_Nesting then
         Error (S, "the program is nested too deeply");
      end if;
   end Nest;

   procedure Expect (S : in out State; K : Token_Kind) is
   begin
      if Kind (S) /= K then
         Error (S, "expected '" & Image (K) & "' but found " & Describe (Cur (S)));
      end if;
      Advance (S);
   end Expect;

   function Accept_Token (S : in out State; K : Token_Kind) return Boolean is
   begin
      if Kind (S) = K then
         Advance (S);
         return True;
      end if;
      return False;
   end Accept_Token;

   function Make (S : State; K : Node_Kind; T : Token) return Node_Access is
     (new Node'(Kind => K, File => S.File, Line => T.Line, Col => T.Col, others => <>));

   function Make (S : State; K : Node_Kind) return Node_Access is
     (Make (S, K, Cur (S)));

   function Identifier (S : in out State) return Unbounded_String is
      T : constant Token := Cur (S);
   begin
      if T.Kind /= T_Identifier then
         Error (S, "expected an identifier but found " & Describe (T));
      end if;
      Advance (S);
      return T.Text;
   end Identifier;

   function Dotted_Name (S : in out State) return Unbounded_String is
      Name : Unbounded_String := Identifier (S);
   begin
      while Kind (S) = T_Dot and then Next_Kind (S) = T_Identifier loop
         Advance (S);
         Append (Name, "." & To_String (Identifier (S)));
      end loop;
      return Name;
   end Dotted_Name;

   function Parse_Type (S : in out State) return Type_Name is
      T      : constant Token := Cur (S);
      Found  : Boolean;
      Result : Type_Name;
   begin
      if T.Kind /= T_Identifier then
         Error (S, "expected a type name but found " & Describe (T));
      end if;
      Result := Type_Of_Name (To_String (T.Text), Found);
      if not Found then
         Error (S, "unknown type '" & To_String (T.Text)
                & "' (types are Integer, Natural, Positive, Boolean, Character, String "
                & "and Vector)");
      end if;
      Advance (S);
      return Result;
   end Parse_Type;

   -------------------------------------------------------------------------
   --  Expressions
   -------------------------------------------------------------------------

   function Parse_Expr (S : in out State) return Node_Access;
   function Parse_Simple (S : in out State) return Node_Access;

   --  ( args ): arguments may be named (Keys => 100), and an index may be
   --  a range (S (2 .. 4))
   procedure Parse_Args (S : in out State; Into : in out Node_Vectors.Vector) is
   begin
      Expect (S, T_Left_Paren);
      if Accept_Token (S, T_Right_Paren) then
         return;
      end if;
      loop
         if Kind (S) = T_Identifier and then Next_Kind (S) = T_Arrow then
            declare
               A : constant Node_Access := Make (S, N_Named_Arg);
            begin
               A.Name := Cur (S).Text;
               Advance (S);
               Advance (S);
               A.Left := Parse_Expr (S);
               Into.Append (A);
            end;
         else
            declare
               E : Node_Access := Parse_Expr (S);
            begin
               if Kind (S) = T_Dot_Dot then
                  declare
                     R : constant Node_Access := Make (S, N_Range);
                  begin
                     Advance (S);
                     R.Left := E;
                     R.Right := Parse_Expr (S);
                     E := R;
                  end;
               end if;
               Into.Append (E);
            end;
         end if;
         exit when not Accept_Token (S, T_Comma);
      end loop;
      Expect (S, T_Right_Paren);
   end Parse_Args;

   function Parse_Name_Expr (S : in out State) return Node_Access is
      N : Node_Access := Make (S, N_Name);
   begin
      N.Name := Dotted_Name (S);
      loop
         if Kind (S) = T_Left_Paren then
            --  As in Ada, X (1) may be a call or an index: that is decided
            --  when it runs, by whether X is a variable
            if N.Kind = N_Name then
               N.Kind := N_Call;
               Parse_Args (S, N.List);
            else
               declare
                  I : constant Node_Access := Make (S, N_Index);
               begin
                  I.Left := N;
                  Parse_Args (S, I.List);
                  N := I;
               end;
            end if;
         elsif Kind (S) = T_Dot and then Next_Kind (S) = T_Identifier then
            declare
               F : constant Node_Access := Make (S, N_Selected);
            begin
               Advance (S);
               F.Name := Identifier (S);
               F.Left := N;
               N := F;
            end;
         elsif Kind (S) = T_Tick then
            declare
               A : constant Node_Access := Make (S, N_Attribute);
            begin
               Advance (S);
               A.Name := Identifier (S);
               A.Left := N;
               if Kind (S) = T_Left_Paren then
                  Parse_Args (S, A.List);
               end if;
               N := A;
            end;
         else
            return N;
         end if;
      end loop;
   end Parse_Name_Expr;

   function Parse_If_Expr (S : in out State) return Node_Access is
      N : constant Node_Access := Make (S, N_If_Expr);
   begin
      Expect (S, K_If);
      loop
         declare
            W : constant Node_Access := Make (S, N_When);
         begin
            W.Left := Parse_Expr (S);
            Expect (S, K_Then);
            W.Right := Parse_Expr (S);
            N.List.Append (W);
         end;
         exit when not Accept_Token (S, K_Elsif);
      end loop;
      Expect (S, K_Else);
      N.Extra := Parse_Expr (S);
      Expect (S, T_Right_Paren);
      return N;
   end Parse_If_Expr;

   function Parse_Primary (S : in out State) return Node_Access is
      T : constant Token := Cur (S);
      N : Node_Access;
   begin
      case T.Kind is
         when T_Integer =>
            N := Make (S, N_Integer);
            N.Int := T.Value;
            Advance (S);
            return N;
         when T_String =>
            N := Make (S, N_String);
            N.Name := T.Text;
            Advance (S);
            return N;
         when T_Character =>
            N := Make (S, N_Character);
            N.Int := T.Value;
            Advance (S);
            return N;
         when T_Left_Paren =>
            --  (Name => ...) is a record, (if ...) an if expression, and
            --  anything else an expression in parentheses
            if Kind_At (S, 1) = T_Identifier and then Kind_At (S, 2) = T_Arrow then
               N := Make (S, N_Record_Aggregate);
               Advance (S);
               loop
                  declare
                     A : constant Node_Access := Make (S, N_Named_Arg);
                  begin
                     A.Name := Identifier (S);
                     Expect (S, T_Arrow);
                     A.Left := Parse_Expr (S);
                     N.List.Append (A);
                  end;
                  exit when not Accept_Token (S, T_Comma);
               end loop;
               Expect (S, T_Right_Paren);
               return N;
            end if;
            Advance (S);
            if Kind (S) = K_If then
               return Parse_If_Expr (S);
            end if;
            N := Parse_Expr (S);
            Expect (S, T_Right_Paren);
            return N;
         when T_Left_Bracket =>
            N := Make (S, N_Vector_Aggregate);
            Advance (S);
            if not Accept_Token (S, T_Right_Bracket) then
               loop
                  N.List.Append (Parse_Expr (S));
                  exit when not Accept_Token (S, T_Comma);
               end loop;
               Expect (S, T_Right_Bracket);
            end if;
            return N;
         when T_Identifier =>
            return Parse_Name_Expr (S);
         when others =>
            Error (S, "expected an expression but found " & Describe (T));
      end case;
   end Parse_Primary;

   function Binary (S : in out State; Op : Token_Kind; Left : Node_Access) return Node_Access is
      N : constant Node_Access := Make (S, N_Binary);
   begin
      Nest (S);  --  A chain of operators builds a deep tree too
      N.Op := Op;
      N.Left := Left;
      return N;
   end Binary;

   --  Precedence as in Ada, from here up: abs, not and ** bind tightest,
   --  then * / mod rem, + - &, relations, and finally and / or / xor
   function Parse_Factor (S : in out State) return Node_Access is
      N : Node_Access;
   begin
      if Kind (S) = K_Abs or else Kind (S) = K_Not then
         N := Make (S, N_Unary);
         N.Op := Kind (S);
         Advance (S);
         N.Left := Parse_Primary (S);
         return N;
      end if;
      N := Parse_Primary (S);
      if Kind (S) = T_Power then
         N := Binary (S, T_Power, N);
         Advance (S);
         N.Right := Parse_Primary (S);
      end if;
      return N;
   end Parse_Factor;

   function Parse_Term (S : in out State) return Node_Access is
      Left : Node_Access := Parse_Factor (S);
   begin
      while Kind (S) in T_Star | T_Slash | K_Mod | K_Rem loop
         Left := Binary (S, Kind (S), Left);
         Advance (S);
         Left.Right := Parse_Factor (S);
      end loop;
      return Left;
   end Parse_Term;

   function Parse_Simple (S : in out State) return Node_Access is
      Left : Node_Access;
   begin
      if Kind (S) = T_Plus or else Kind (S) = T_Minus then
         Left := Make (S, N_Unary);
         Left.Op := Kind (S);
         Advance (S);
         Left.Left := Parse_Term (S);
      else
         Left := Parse_Term (S);
      end if;
      while Kind (S) in T_Plus | T_Minus | T_Ampersand loop
         Left := Binary (S, Kind (S), Left);
         Advance (S);
         Left.Right := Parse_Term (S);
      end loop;
      return Left;
   end Parse_Simple;

   function Parse_Relation (S : in out State) return Node_Access is
      Left : constant Node_Access := Parse_Simple (S);
      N    : Node_Access;
   begin
      case Kind (S) is
         when T_Eq | T_Ne | T_Lt | T_Le | T_Gt | T_Ge =>
            N := Binary (S, Kind (S), Left);
            Advance (S);
            N.Right := Parse_Simple (S);
            return N;
         when K_In | K_Not =>
            --  After an expression, "not" can only start "not in"
            if Kind (S) = K_Not and then Next_Kind (S) /= K_In then
               return Left;
            end if;
            N := Make (S, N_Membership);
            N.Flag := Accept_Token (S, K_Not);
            Expect (S, K_In);
            N.Left := Left;
            N.Right := Parse_Simple (S);
            Expect (S, T_Dot_Dot);
            N.Extra := Parse_Simple (S);
            return N;
         when others =>
            return Left;
      end case;
   end Parse_Relation;

   function Parse_Expr (S : in out State) return Node_Access is
      Saved : constant Natural := S.Nesting;
      Left  : Node_Access;
   begin
      Nest (S);
      Left := Parse_Relation (S);
      while Kind (S) in K_And | K_Or | K_Xor loop
         Left := Binary (S, Kind (S), Left);
         Advance (S);
         --  Flag marks the short-circuit forms "and then" and "or else"
         if Left.Op = K_And and then Kind (S) = K_Then then
            Left.Flag := True;
            Advance (S);
         elsif Left.Op = K_Or and then Kind (S) = K_Else then
            Left.Flag := True;
            Advance (S);
         end if;
         Left.Right := Parse_Relation (S);
      end loop;
      S.Nesting := Saved;
      return Left;
   end Parse_Expr;

   -------------------------------------------------------------------------
   --  Statements
   -------------------------------------------------------------------------

   procedure Parse_Statements (S : in out State; Into : in out Node_Vectors.Vector);

   function Parse_Pragma (S : in out State) return Node_Access is
      N : constant Node_Access := Make (S, N_Pragma);
   begin
      Expect (S, K_Pragma);
      N.Name := Identifier (S);
      if Kind (S) = T_Left_Paren then
         Parse_Args (S, N.List);
      end if;
      Expect (S, T_Semicolon);
      return N;
   end Parse_Pragma;

   procedure Parse_Declaration (S : in out State; Into : in out Node_Vectors.Vector) is
      Names       : Token_Vectors.Vector;
      Is_Constant : Boolean;
      T           : Type_Name := T_Any;
      Init        : Node_Access := null;
   begin
      loop
         if Kind (S) /= T_Identifier then
            Error (S, "expected an identifier but found " & Describe (Cur (S)));
         end if;
         Names.Append (Cur (S));
         Advance (S);
         exit when not Accept_Token (S, T_Comma);
      end loop;
      Expect (S, T_Colon);
      if Accept_Token (S, K_Exception) then
         Expect (S, T_Semicolon);
         for Name_Token of Names loop
            declare
               N : constant Node_Access := Make (S, N_Exception_Decl, Name_Token);
            begin
               N.Name := Name_Token.Text;
               Into.Append (N);
            end;
         end loop;
         return;
      end if;
      Is_Constant := Accept_Token (S, K_Constant);
      if Kind (S) = T_Identifier then
         T := Parse_Type (S);
      end if;
      if Accept_Token (S, T_Assign) then
         Init := Parse_Expr (S);
      elsif Is_Constant then
         Error (S, "a constant needs a value");
      elsif T = T_Any then
         Error (S, "expected a type or ':=' but found " & Describe (Cur (S)));
      end if;
      Expect (S, T_Semicolon);

      for Name_Token of Names loop
         declare
            N : constant Node_Access := Make (S, N_Declare, Name_Token);
         begin
            N.Name := Name_Token.Text;
            N.Decl_Type := T;
            N.Flag := Is_Constant;
            N.Left := Init;
            Into.Append (N);
         end;
      end loop;
   end Parse_Declaration;

   --  when [E :] Name | Other | others => statements ...
   procedure Parse_Handlers (S : in out State; Into : in out Node_Vectors.Vector) is
   begin
      if Kind (S) /= K_When then
         Error (S, "expected 'when' after 'exception' but found " & Describe (Cur (S)));
      end if;
      while Kind (S) = K_When loop
         declare
            W : constant Node_Access := Make (S, N_When);
         begin
            Advance (S);
            if Kind (S) = T_Identifier and then Next_Kind (S) = T_Colon then
               W.Name := Cur (S).Text;
               Advance (S);
               Advance (S);
            end if;
            loop
               if Kind (S) = K_Others then
                  W.List.Append (Make (S, N_Others));
                  Advance (S);
               else
                  declare
                     C : constant Node_Access := Make (S, N_Name);
                  begin
                     C.Name := Dotted_Name (S);
                     W.List.Append (C);
                  end;
               end if;
               exit when not Accept_Token (S, T_Bar);
            end loop;
            Expect (S, T_Arrow);
            Parse_Statements (S, W.Stmts);
            Into.Append (W);
         end;
      end loop;
   end Parse_Handlers;

   procedure Parse_Loop_Body (S : in out State; N : Node_Access) is
   begin
      S.Loop_Depth := S.Loop_Depth + 1;
      Parse_Statements (S, N.Stmts);
      S.Loop_Depth := S.Loop_Depth - 1;
      Expect (S, K_End);
      Expect (S, K_Loop);
      Expect (S, T_Semicolon);
   end Parse_Loop_Body;

   procedure Parse_Statement (S : in out State; Into : in out Node_Vectors.Vector) is
      T : constant Token := Cur (S);
      N : Node_Access;
   begin
      case T.Kind is
         when K_Null =>
            N := Make (S, N_Null);
            Advance (S);
            Expect (S, T_Semicolon);

         when K_If =>
            N := Make (S, N_If);
            Advance (S);
            loop
               declare
                  W : constant Node_Access := Make (S, N_When);
               begin
                  W.Left := Parse_Expr (S);
                  Expect (S, K_Then);
                  Parse_Statements (S, W.Stmts);
                  N.List.Append (W);
               end;
               exit when not Accept_Token (S, K_Elsif);
            end loop;
            if Accept_Token (S, K_Else) then
               Parse_Statements (S, N.Else_Stmts);
            end if;
            Expect (S, K_End);
            Expect (S, K_If);
            Expect (S, T_Semicolon);

         when K_Case =>
            N := Make (S, N_Case);
            Advance (S);
            N.Left := Parse_Expr (S);
            Expect (S, K_Is);
            if Kind (S) /= K_When then
               Error (S, "expected 'when' but found " & Describe (Cur (S)));
            end if;
            while Kind (S) = K_When loop
               declare
                  W : constant Node_Access := Make (S, N_When);
               begin
                  Advance (S);
                  loop
                     if Kind (S) = K_Others then
                        W.List.Append (Make (S, N_Others));
                        Advance (S);
                     else
                        declare
                           C : Node_Access := Parse_Simple (S);
                        begin
                           if Kind (S) = T_Dot_Dot then
                              declare
                                 R : constant Node_Access := Make (S, N_Range);
                              begin
                                 Advance (S);
                                 R.Left := C;
                                 R.Right := Parse_Simple (S);
                                 C := R;
                              end;
                           end if;
                           W.List.Append (C);
                        end;
                     end if;
                     exit when not Accept_Token (S, T_Bar);
                  end loop;
                  Expect (S, T_Arrow);
                  Parse_Statements (S, W.Stmts);
                  N.List.Append (W);
               end;
            end loop;
            Expect (S, K_End);
            Expect (S, K_Case);
            Expect (S, T_Semicolon);

         when K_While =>
            N := Make (S, N_While);
            Advance (S);
            N.Left := Parse_Expr (S);
            Expect (S, K_Loop);
            Parse_Loop_Body (S, N);

         when K_For =>
            N := Make (S, N_For);
            Advance (S);
            N.Name := Identifier (S);
            if Accept_Token (S, K_Of) then
               N.Int := 1;  --  for X of Container
               N.Left := Parse_Expr (S);
            else
               Expect (S, K_In);
               N.Flag := Accept_Token (S, K_Reverse);
               N.Left := Parse_Simple (S);
               Expect (S, T_Dot_Dot);
               N.Right := Parse_Simple (S);
            end if;
            Expect (S, K_Loop);
            Parse_Loop_Body (S, N);

         when K_Loop =>
            N := Make (S, N_Loop);
            Advance (S);
            Parse_Loop_Body (S, N);

         when K_Exit =>
            if S.Loop_Depth = 0 then
               Error (S, "exit outside a loop");
            end if;
            N := Make (S, N_Exit);
            Advance (S);
            if Accept_Token (S, K_When) then
               N.Left := Parse_Expr (S);
            end if;
            Expect (S, T_Semicolon);

         when K_Raise =>
            N := Make (S, N_Raise);
            Advance (S);
            if Kind (S) = T_Identifier then
               N.Name := Dotted_Name (S);
               if Accept_Token (S, K_With) then
                  N.Left := Parse_Expr (S);
               end if;
            end if;
            Expect (S, T_Semicolon);

         when K_Return =>
            N := Make (S, N_Return);
            Advance (S);
            if Kind (S) /= T_Semicolon then
               N.Left := Parse_Expr (S);
            end if;
            Expect (S, T_Semicolon);

         when K_Declare | K_Begin =>
            N := Make (S, N_Block);
            if Accept_Token (S, K_Declare) then
               while Kind (S) /= K_Begin loop
                  if Kind (S) = T_Identifier then
                     Parse_Declaration (S, N.Stmts);
                  else
                     Error (S, "expected a declaration or 'begin' but found "
                            & Describe (Cur (S)));
                  end if;
               end loop;
            end if;
            Expect (S, K_Begin);
            Parse_Statements (S, N.Stmts);
            if Accept_Token (S, K_Exception) then
               Parse_Handlers (S, N.Else_Stmts);
            end if;
            Expect (S, K_End);
            Expect (S, T_Semicolon);

         when K_Pragma =>
            N := Parse_Pragma (S);

         when K_Procedure | K_Function =>
            Error (S, "procedures and functions can only be declared at the outermost level");

         when T_Identifier =>
            --  Unlike Ada, declarations may appear among the statements
            if Next_Kind (S) = T_Colon or else Next_Kind (S) = T_Comma then
               Parse_Declaration (S, Into);
               return;
            end if;
            declare
               Target : constant Node_Access := Parse_Name_Expr (S);
            begin
               if Kind (S) = T_Assign then
                  if Target.Kind not in N_Name | N_Call | N_Index | N_Selected then
                     Error_At (S, T, "only variables, their elements and their fields "
                               & "can be assigned to");
                  end if;
                  N := Make (S, N_Assign, T);
                  N.Name := Target.Name;
                  N.Extra := Target;
                  Advance (S);
                  N.Left := Parse_Expr (S);
               elsif Target.Kind in N_Name | N_Call then
                  N := Make (S, N_Call_Stmt, T);
                  N.Left := Target;
               else
                  Error_At (S, T, "expected a statement");
               end if;
               Expect (S, T_Semicolon);
            end;

         when others =>
            Error (S, "expected a statement but found " & Describe (T));
      end case;
      Into.Append (N);
   end Parse_Statement;

   procedure Parse_Statements (S : in out State; Into : in out Node_Vectors.Vector) is
      Saved : constant Natural := S.Nesting;
   begin
      Nest (S);
      while Kind (S) not in K_End | K_Else | K_Elsif | K_When | K_Exception | T_EOF loop
         Parse_Statement (S, Into);
      end loop;
      S.Nesting := Saved;
   end Parse_Statements;

   function Parse_Subprogram (S : in out State) return Node_Access is
      N           : constant Node_Access := Make (S, N_Subprogram);
      Saved_Depth : constant Natural := S.Loop_Depth;
   begin
      N.Flag := Kind (S) = K_Function;
      Advance (S);
      N.Name := Identifier (S);

      if Accept_Token (S, T_Left_Paren) then
         loop
            declare
               Names   : Token_Vectors.Vector;
               Mode    : Param_Mode := Mode_In;
               T       : Type_Name := T_Any;
               Default : Node_Access := null;
            begin
               loop
                  if Kind (S) /= T_Identifier then
                     Error (S, "expected a parameter name but found " & Describe (Cur (S)));
                  end if;
                  Names.Append (Cur (S));
                  Advance (S);
                  exit when not Accept_Token (S, T_Comma);
               end loop;
               if Accept_Token (S, T_Colon) then
                  if Accept_Token (S, K_In) then
                     if Accept_Token (S, K_Out) then
                        Mode := Mode_In_Out;
                     end if;
                  elsif Accept_Token (S, K_Out) then
                     Mode := Mode_Out;
                  end if;
                  if Kind (S) = T_Identifier then
                     T := Parse_Type (S);
                  end if;
               end if;
               if Accept_Token (S, T_Assign) then
                  if Mode /= Mode_In then
                     Error (S, "only 'in' parameters can have a default value");
                  end if;
                  Default := Parse_Expr (S);
               end if;
               for Name_Token of Names loop
                  declare
                     P : constant Node_Access := Make (S, N_Param, Name_Token);
                  begin
                     P.Name := Name_Token.Text;
                     P.Mode := Mode;
                     P.Decl_Type := T;
                     P.Left := Default;
                     N.List.Append (P);
                  end;
               end loop;
            end;
            exit when not Accept_Token (S, T_Semicolon);
         end loop;
         Expect (S, T_Right_Paren);
      end if;

      if N.Flag then
         Expect (S, K_Return);
         if Kind (S) = T_Identifier then
            N.Decl_Type := Parse_Type (S);
         end if;
      end if;

      Expect (S, K_Is);
      while Kind (S) /= K_Begin loop
         if Kind (S) = K_Pragma then
            declare
               P : constant Node_Access := Parse_Pragma (S);
            begin
               if To_String (P.Name) = "command" and then P.List.Is_Empty then
                  N.Int := 1;  --  The procedure becomes an editor command
               else
                  Error_At (S, Cur (S), "unknown pragma '" & To_String (P.Name)
                            & "' (only 'pragma Command;' is allowed here)");
               end if;
            end;
         elsif Kind (S) = T_Identifier then
            Parse_Declaration (S, N.Stmts);
         else
            Error (S, "expected a declaration or 'begin' but found " & Describe (Cur (S)));
         end if;
      end loop;
      Advance (S);

      --  An exit in the body cannot leave a loop outside the subprogram
      S.Loop_Depth := 0;
      Parse_Statements (S, N.Stmts);
      if Accept_Token (S, K_Exception) then
         Parse_Handlers (S, N.Else_Stmts);
      end if;
      S.Loop_Depth := Saved_Depth;

      Expect (S, K_End);
      if Kind (S) = T_Identifier then
         if Cur (S).Text /= N.Name then
            Error (S, "'end " & To_String (Cur (S).Text) & "' does not match '"
                   & To_String (N.Name) & "'");
         end if;
         Advance (S);
      end if;
      Expect (S, T_Semicolon);
      return N;
   end Parse_Subprogram;

   -------------------------------------------------------------------------

   function New_State (Source : String; File_Name : String) return State is
   begin
      return S : State do
         S.Tokens := Tokenize (Source, File_Name);
         S.File := Register_File (File_Name);
         S.File_Name := To_Unbounded_String (File_Name);
      end return;
   end New_State;

   function Parse (Source : String; File_Name : String) return Node_Vectors.Vector is
      S      : State := New_State (Source, File_Name);
      Result : Node_Vectors.Vector;
   begin
      while Kind (S) /= T_EOF loop
         case Kind (S) is
            when K_Procedure | K_Function =>
               Result.Append (Parse_Subprogram (S));
            when K_With | K_Use =>
               --  Accepted for Ada familiarity and ignored
               while Kind (S) not in T_Semicolon | T_EOF loop
                  Advance (S);
               end loop;
               Expect (S, T_Semicolon);
            when K_End | K_Else | K_Elsif | K_When | K_Exception =>
               Error (S, "unexpected " & Describe (Cur (S)));
            when others =>
               Parse_Statement (S, Result);
         end case;
      end loop;
      return Result;
   end Parse;

   function Parse_Expression (Source : String; File_Name : String) return Node_Access is
      S : State := New_State (Source, File_Name);
      N : Node_Access;
   begin
      N := Parse_Expr (S);
      if Kind (S) /= T_EOF then
         Error (S, "unexpected " & Describe (Cur (S)) & " after the expression");
      end if;
      return N;
   end Parse_Expression;

end Scripts.Parser;
