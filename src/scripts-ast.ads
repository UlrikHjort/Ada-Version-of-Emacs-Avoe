-- ***************************************************************************
--                             Avoe - Scripts.AST
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

--  Syntax trees of Avoe script.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Scripts.Lexer;         use Scripts.Lexer;
with Scripts.Values;        use Scripts.Values;

package Scripts.AST is

   type Node_Kind is
     (--  Expressions
      N_Integer,      --  Int
      N_String,       --  Name = value
      N_Character,    --  Int = code
      N_Name,         --  Name (lower case, may be dotted)
      N_Call,         --  Name, List = arguments (also string indexing)
      N_Unary,        --  Op, Left
      N_Binary,       --  Op, Left, Right; Flag = short circuit
      N_Attribute,    --  Left = prefix, Name = attribute, List = arguments
      N_If_Expr,      --  List = N_When (Left cond, Right value), Extra = else
      N_Membership,   --  Left in Right .. Extra; Flag = not in
      N_Range,        --  Left .. Right
      N_Named_Arg,    --  Name => Left
      N_Others,
      N_Vector_Aggregate,  --  List = elements: [a, b]
      N_Record_Aggregate,  --  List = N_Named_Arg: (X => 1, Y => 2)
      N_Index,        --  Left = prefix, List = index or range: F (X) (2)
      N_Selected,     --  Left = prefix, Name = field: V (2).Name

      --  Statements
      N_Declare,      --  Name, Decl_Type, Flag = constant, Left = initial value
      N_Exception_Decl,  --  Name : exception;
      N_Raise,        --  Name (empty for "raise;"), Left = message or null
      N_Assign,       --  Extra = target (name, element or field) := Left
      N_Call_Stmt,    --  Left = N_Name or N_Call
      N_If,           --  List = N_When (Left cond, Stmts), Else_Stmts
      N_Case,         --  Left = selector, List = N_When (List choices, Stmts)
      N_When,
      N_While,        --  Left cond, Stmts
      N_For,          --  Name, Left .. Right, Flag = reverse, Stmts;
                      --  Int = 1: "for Name of Left"
      N_Loop,         --  Stmts
      N_Exit,         --  Left = condition or null
      N_Return,       --  Left = value or null
      N_Null,
      N_Block,        --  Stmts, Else_Stmts = exception handlers (N_When:
                      --  List = exception names or N_Others, Name = the
                      --  optional "E :" variable, Stmts)
      N_Pragma,       --  Name, List
      N_Subprogram,   --  Name, Flag = function, List = N_Param, Decl_Type =
                      --  result, Stmts = declarations and body, Else_Stmts
                      --  = exception handlers, Int = 1 if it is an editor
                      --  command
      N_Param);       --  Name, Mode, Decl_Type, Left = default

   type Param_Mode is (Mode_In, Mode_Out, Mode_In_Out);

   type Node;
   type Node_Access is access all Node;

   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node_Access);

   type Node is record
      Kind       : Node_Kind;
      File       : Natural := 0;
      Line       : Positive := 1;
      Col        : Positive := 1;
      Name       : Unbounded_String;
      Int        : Long_Long_Integer := 0;
      Op         : Token_Kind := T_EOF;
      Left       : Node_Access;
      Right      : Node_Access;
      Extra      : Node_Access;
      List       : Node_Vectors.Vector;
      Stmts      : Node_Vectors.Vector;
      Else_Stmts : Node_Vectors.Vector;
      Flag       : Boolean := False;
      Decl_Type  : Type_Name := T_Any;
      Mode       : Param_Mode := Mode_In;
   end record;

   function Register_File (Name : String) return Natural;
   function File_Name (Id : Natural) return String;

   function Where (N : Node_Access) return String;
   --  "file:line:col"

end Scripts.AST;
