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

with Ada.Characters.Latin_1;
with Utils;

package body Scripts.Lexer is

   package L1 renames Ada.Characters.Latin_1;

   function Lower (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         C := Utils.To_Lower (C);
      end loop;
      return R;
   end Lower;

   function Image (Kind : Token_Kind) return String is
   begin
      case Kind is
         when T_EOF         => return "end of input";
         when T_Identifier  => return "identifier";
         when T_Integer     => return "integer";
         when T_String      => return "string";
         when T_Character   => return "character";
         when T_Left_Paren  => return "(";
         when T_Right_Paren => return ")";
         when T_Left_Bracket  => return "[";
         when T_Right_Bracket => return "]";
         when T_Comma       => return ",";
         when T_Semicolon   => return ";";
         when T_Colon       => return ":";
         when T_Assign      => return ":=";
         when T_Arrow       => return "=>";
         when T_Dot_Dot     => return "..";
         when T_Dot         => return ".";
         when T_Tick        => return "'";
         when T_Bar         => return "|";
         when T_Plus        => return "+";
         when T_Minus       => return "-";
         when T_Star        => return "*";
         when T_Slash       => return "/";
         when T_Power       => return "**";
         when T_Ampersand   => return "&";
         when T_Eq          => return "=";
         when T_Ne          => return "/=";
         when T_Lt          => return "<";
         when T_Le          => return "<=";
         when T_Gt          => return ">";
         when T_Ge          => return ">=";
         when Keyword =>
            declare
               S : constant String := Token_Kind'Image (Kind);
            begin
               return Lower (S (S'First + 2 .. S'Last));
            end;
      end case;
   end Image;

   --  The keywords are the K_ literals of Token_Kind, so they are listed in
   --  one place only
   function Keyword_Of (Word : String) return Token_Kind is
   begin
      for K in Keyword loop
         if Image (K) = Word then
            return K;
         end if;
      end loop;
      return T_Identifier;
   end Keyword_Of;

   function Tokenize (Source : String; File : String) return Token_Vectors.Vector is
      Result     : Token_Vectors.Vector;
      I          : Integer := Source'First;
      Line       : Positive := 1;
      Line_Start : Integer := Source'First;

      procedure Error (Msg : String; At_Pos : Integer) with No_Return;

      procedure Error (Msg : String; At_Pos : Integer) is
      begin
         raise Script_Error with
           File & ":" & Utils.Img (Line) & ":"
           & Utils.Img (At_Pos - Line_Start + 1) & ": " & Msg;
      end Error;

      procedure Add
        (Kind  : Token_Kind;
         Start : Integer;
         Text  : String := "";
         Value : Long_Long_Integer := 0) is
      begin
         Result.Append
           ((Kind  => Kind,
             Text  => To_Unbounded_String (Text),
             Value => Value,
             Line  => Line,
             Col   => Start - Line_Start + 1));
      end Add;

      function At_Char (J : Integer) return Character is
        (if J <= Source'Last then Source (J) else L1.NUL);

      function Is_Letter (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z');

      function Digit_Value (C : Character) return Integer is
        (case C is
            when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
            when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
            when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
            when others     => 99);

   begin
      while I <= Source'Last loop
         declare
            C : constant Character := Source (I);
         begin
            if C = L1.LF then
               Line := Line + 1;
               I := I + 1;
               Line_Start := I;

            elsif C = ' ' or else C = L1.HT or else C = L1.CR or else C = L1.FF then
               I := I + 1;

            elsif C = '-' and then At_Char (I + 1) = '-' then
               while I <= Source'Last and then Source (I) /= L1.LF loop
                  I := I + 1;
               end loop;

            elsif Is_Letter (C) then
               declare
                  J : Integer := I;
               begin
                  while J <= Source'Last
                    and then (Is_Letter (Source (J))
                              or else Source (J) in '0' .. '9'
                              or else Source (J) = '_')
                  loop
                     J := J + 1;
                  end loop;
                  declare
                     --  As in Ada, case does not matter in names
                     Word : constant String := Lower (Source (I .. J - 1));
                  begin
                     Add (Keyword_Of (Word), I, Word);
                  end;
                  I := J;
               end;

            elsif C in '0' .. '9' then
               declare
                  V : Long_Long_Integer := 0;
                  J : Integer := I;

                  procedure Scan (Base : Long_Long_Integer) is
                     D   : Integer;
                     Any : Boolean := False;
                  begin
                     loop
                        if At_Char (J) = '_' and then Any then
                           J := J + 1;
                        else
                           D := Digit_Value (At_Char (J));
                           exit when Long_Long_Integer (D) >= Base;
                           if V > (Long_Long_Integer'Last - Long_Long_Integer (D)) / Base then
                              Error ("integer literal is too large", I);
                           end if;
                           V := V * Base + Long_Long_Integer (D);
                           Any := True;
                           J := J + 1;
                        end if;
                     end loop;
                     if not Any then
                        Error ("digits expected", J);
                     end if;
                  end Scan;
               begin
                  Scan (10);
                  --  An Ada based literal such as 16#FF# or 2#1010#
                  if At_Char (J) = '#' then
                     if V < 2 or else V > 16 then
                        Error ("the base must be between 2 and 16", I);
                     end if;
                     declare
                        Base : constant Long_Long_Integer := V;
                     begin
                        J := J + 1;
                        V := 0;
                        Scan (Base);
                     end;
                     if At_Char (J) /= '#' then
                        Error ("missing '#' at end of based literal", J);
                     end if;
                     J := J + 1;
                  end if;
                  if Is_Letter (At_Char (J)) or else At_Char (J) = '_' then
                     Error ("invalid character in number", J);
                  end if;
                  Add (T_Integer, I, "", V);
                  I := J;
               end;

            elsif C = '"' then
               declare
                  J    : Integer := I + 1;
                  Text : Unbounded_String;
               begin
                  loop
                     if J > Source'Last or else Source (J) = L1.LF then
                        Error ("unterminated string", I);
                     elsif Source (J) = '"' then
                        --  As in Ada, "" inside a string is one quote
                        exit when At_Char (J + 1) /= '"';
                        Append (Text, '"');
                        J := J + 2;
                     else
                        Append (Text, Source (J));
                        J := J + 1;
                     end if;
                  end loop;
                  Add (T_String, I, To_String (Text));
                  I := J + 1;
               end;

            elsif C = ''' then
               declare
                  Previous : constant Token_Kind :=
                    (if Result.Is_Empty then T_EOF else Result.Last_Element.Kind);
               begin
                  --  'x' is a character literal, but after a name or a closing
                  --  bracket ' starts an attribute, as in Character'Val ('a')
                  if At_Char (I + 2) = '''
                    and then I + 1 <= Source'Last
                    and then Previous not in T_Identifier | T_Right_Paren | T_Right_Bracket
                  then
                     Add (T_Character, I, (1 => Source (I + 1)),
                          Long_Long_Integer (Character'Pos (Source (I + 1))));
                     I := I + 3;
                  else
                     Add (T_Tick, I);
                     I := I + 1;
                  end if;
               end;

            elsif Character'Pos (C) >= 128 then
               Error ("non-ASCII character outside a string", I);

            else
               declare
                  Two : constant String := C & At_Char (I + 1);
               begin
                  if Two = ":=" then
                     Add (T_Assign, I);
                     I := I + 2;
                  elsif Two = "=>" then
                     Add (T_Arrow, I);
                     I := I + 2;
                  elsif Two = ".." then
                     Add (T_Dot_Dot, I);
                     I := I + 2;
                  elsif Two = "**" then
                     Add (T_Power, I);
                     I := I + 2;
                  elsif Two = "/=" then
                     Add (T_Ne, I);
                     I := I + 2;
                  elsif Two = "<=" then
                     Add (T_Le, I);
                     I := I + 2;
                  elsif Two = ">=" then
                     Add (T_Ge, I);
                     I := I + 2;
                  else
                     case C is
                        when '(' => Add (T_Left_Paren, I);
                        when ')' => Add (T_Right_Paren, I);
                        when '[' => Add (T_Left_Bracket, I);
                        when ']' => Add (T_Right_Bracket, I);
                        when ',' => Add (T_Comma, I);
                        when ';' => Add (T_Semicolon, I);
                        when ':' => Add (T_Colon, I);
                        when '.' => Add (T_Dot, I);
                        when '|' => Add (T_Bar, I);
                        when '+' => Add (T_Plus, I);
                        when '-' => Add (T_Minus, I);
                        when '*' => Add (T_Star, I);
                        when '/' => Add (T_Slash, I);
                        when '&' => Add (T_Ampersand, I);
                        when '=' => Add (T_Eq, I);
                        when '<' => Add (T_Lt, I);
                        when '>' => Add (T_Gt, I);
                        when others =>
                           Error ("unexpected character '" & C & "'", I);
                     end case;
                     I := I + 1;
                  end if;
               end;
            end if;
         end;
      end loop;

      Add (T_EOF, I);
      return Result;
   end Tokenize;

end Scripts.Lexer;
