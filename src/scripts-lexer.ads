-- ***************************************************************************
--                            Avoe - Scripts.Lexer
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Scripts.Lexer is

   type Token_Kind is
     (T_EOF, T_Identifier, T_Integer, T_String, T_Character,
      T_Left_Paren, T_Right_Paren, T_Left_Bracket, T_Right_Bracket,
      T_Comma, T_Semicolon, T_Colon,
      T_Assign, T_Arrow, T_Dot_Dot, T_Dot, T_Tick, T_Bar,
      T_Plus, T_Minus, T_Star, T_Slash, T_Power, T_Ampersand,
      T_Eq, T_Ne, T_Lt, T_Le, T_Gt, T_Ge,
      K_Abs, K_And, K_Begin, K_Case, K_Constant, K_Declare, K_Else, K_Elsif,
      K_End, K_Exception, K_Exit, K_For, K_Function, K_If, K_In, K_Is, K_Loop,
      K_Mod, K_Not, K_Null, K_Of, K_Or, K_Others, K_Out, K_Pragma, K_Procedure,
      K_Raise, K_Rem, K_Return, K_Reverse, K_Then, K_Use, K_When, K_While,
      K_With, K_Xor);

   subtype Keyword is Token_Kind range K_Abs .. K_Xor;

   type Token is record
      Kind  : Token_Kind := T_EOF;
      Text  : Unbounded_String;          --  Identifier (lower case) or string
      Value : Long_Long_Integer := 0;    --  Integer value or character code
      Line  : Positive := 1;
      Col   : Positive := 1;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   function Tokenize (Source : String; File : String) return Token_Vectors.Vector;
   --  The result always ends with a T_EOF token.

   function Image (Kind : Token_Kind) return String;

end Scripts.Lexer;
