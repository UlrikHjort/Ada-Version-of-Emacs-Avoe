-- ***************************************************************************
--                             Avoe - Ada_Indent
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

package body Ada_Indent is

   package L1 renames Ada.Characters.Latin_1;

   Max_Line  : constant := 4096;
   Max_Steps : constant := 500;  --  How far back to look

   function Is_Word_Char (C : Character) return Boolean is
     (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');

   --  The line's code in lower case with comments removed and the insides
   --  of string and character literals blanked.  Byte offsets from the
   --  line start are preserved; trailing blanks are removed.
   function Code_Of (B : Buffer; Start : Natural) return String is
      Stop : constant Natural := Natural'Min (Line_End (B, Start), Start + Max_Line);
      S    : String := Slice (B, Start, Stop);
      I    : Integer := S'First;
      Last : Integer := S'Last;
   begin
      while I <= S'Last loop
         if S (I) = '-' and then I < S'Last and then S (I + 1) = '-' then
            Last := I - 1;
            exit;
         elsif S (I) = '"' then
            I := I + 1;
            while I <= S'Last and then S (I) /= '"' loop
               S (I) := 'x';
               I := I + 1;
            end loop;
            I := I + 1;
         elsif S (I) = ''' and then I + 2 <= S'Last and then S (I + 2) = '''
           and then (I = S'First or else not Is_Word_Char (S (I - 1)))
         then
            S (I + 1) := 'x';
            I := I + 3;
         else
            S (I) := Utils.To_Lower (S (I));
            I := I + 1;
         end if;
      end loop;
      while Last >= S'First and then S (Last) in ' ' | L1.HT | L1.CR loop
         Last := Last - 1;
      end loop;
      return S (S'First .. Last);
   end Code_Of;

   function Trim_Left (S : String) return String is
      I : Integer := S'First;
   begin
      while I <= S'Last and then S (I) in ' ' | L1.HT loop
         I := I + 1;
      end loop;
      return S (I .. S'Last);
   end Trim_Left;

   function Indent_Of (B : Buffer; Start : Natural) return Natural is
      Len : constant Natural := Length (B);
      P   : Natural := Start;
   begin
      while P < Len and then Char_At (B, P) in ' ' | L1.HT loop
         P := P + 1;
      end loop;
      return Column_Of (B, P);
   end Indent_Of;

   function Ends_With_Word (Code, Word : String) return Boolean is
     (Code'Length >= Word'Length
      and then Code (Code'Last - Word'Length + 1 .. Code'Last) = Word
      and then (Code'Length = Word'Length
                or else not Is_Word_Char (Code (Code'Last - Word'Length))));

   function Starts_With_Word (Code, Word : String) return Boolean is
     (Code'Length >= Word'Length
      and then Code (Code'First .. Code'First + Word'Length - 1) = Word
      and then (Code'Length = Word'Length
                or else not Is_Word_Char (Code (Code'First + Word'Length))));

   --  Does the line end so that the next line is indented one level more?
   function Is_Opener (Code : String) return Boolean is
      T : constant String := Trim_Left (Code);
   begin
      --  These end in "else" and "then" but continue an expression
      if Ends_With_Word (Code, "or else") or else Ends_With_Word (Code, "and then") then
         return False;
      end if;
      return Ends_With_Word (Code, "is")
        or else Ends_With_Word (Code, "begin")
        or else Ends_With_Word (Code, "then")
        or else Ends_With_Word (Code, "else")
        or else Ends_With_Word (Code, "loop")
        or else Ends_With_Word (Code, "declare")
        or else Ends_With_Word (Code, "record")
        or else Ends_With_Word (Code, "do")
        or else Ends_With_Word (Code, "private")
        or else Ends_With_Word (Code, "exception")
        or else Ends_With_Word (Code, "select")
        or else Ends_With_Word (Code, "generic")
        or else (Starts_With_Word (T, "when") and then Ends_With_Word (Code, "=>"));
   end Is_Opener;

   --  A statement that goes on on the next line, such as a long call
   function Is_Incomplete (Code : String) return Boolean is
     (Code'Length > 0
      and then Code (Code'Last) /= ';'
      and then not Is_Opener (Code));

   --  Opening minus closing parentheses
   function Paren_Delta (Code : String) return Integer is
      D : Integer := 0;
   begin
      for C of Code loop
         if C = '(' then
            D := D + 1;
         elsif C = ')' then
            D := D - 1;
         end if;
      end loop;
      return D;
   end Paren_Delta;

   --  Offset of the innermost unclosed '(' or -1
   function Unclosed_Paren (Code : String) return Integer is
      Stack : array (1 .. 64) of Integer;
      Depth : Natural := 0;
   begin
      for I in Code'Range loop
         if Code (I) = '(' then
            if Depth < Stack'Last then
               Depth := Depth + 1;
               Stack (Depth) := I - Code'First;
            end if;
         elsif Code (I) = ')' and then Depth > 0 then
            Depth := Depth - 1;
         end if;
      end loop;
      return (if Depth = 0 then -1 else Stack (Depth));
   end Unclosed_Paren;

   --  Start of the previous line that contains code, or -1
   function Previous_Code_Line (B : Buffer; Start : Natural) return Integer is
      S : Natural := Start;
   begin
      for I in 1 .. Max_Steps loop
         exit when S = 0;
         S := Line_Start (B, S - 1);
         if Code_Of (B, S) /= "" then
            return S;
         end if;
      end loop;
      return -1;
   end Previous_Code_Line;

   --  The first line of the statement that ends on the line at P
   function Statement_Start (B : Buffer; P : Natural) return Natural is
      Q    : Natural := P;
      Need : Integer := -Paren_Delta (Code_Of (B, P));
   begin
      for I in 1 .. Max_Steps loop
         declare
            R : constant Integer := Previous_Code_Line (B, Q);
         begin
            exit when R < 0;
            declare
               RC : constant String := Code_Of (B, R);
            begin
               if Need > 0 then
                  Need := Need - Paren_Delta (RC);
               elsif not Is_Incomplete (RC) then
                  exit;
               end if;
               Q := R;
            end;
         end;
      end loop;
      return Q;
   end Statement_Start;

   function Indentation_For (B : Buffer; Start : Natural) return Natural is
      P       : constant Integer := Previous_Code_Line (B, Start);
      Current : constant String := Trim_Left (Code_Of (B, Start));
      Result  : Integer;
   begin
      if P < 0 then
         return 0;
      end if;

      declare
         PC   : constant String := Code_Of (B, P);
         Open : constant Integer := Unclosed_Paren (PC);
      begin
         if Open >= 0 then
            --  Align after an unclosed parenthesis
            Result := Column_Of (B, P + Open) + 1;
         else
            declare
               Stmt : constant Natural := Statement_Start (B, P);
               Base : constant Natural := Indent_Of (B, Stmt);
            begin
               if Is_Opener (PC) then
                  Result := Base + Indent_Width;
               elsif PC (PC'Last) = ';' then
                  Result := Base;
               elsif Stmt = P then
                  --  The second line of a statement; later lines line up with it
                  Result := Base + Continuation_Width;
               else
                  Result := Indent_Of (B, P);
               end if;
            end;

            --  Lines that close or divide a block go one level out.  Not a
            --  when right after "case ... is", exception or select: the
            --  alternatives are indented inside those.
            if Starts_With_Word (Current, "end")
              or else Starts_With_Word (Current, "else")
              or else Starts_With_Word (Current, "elsif")
              or else Starts_With_Word (Current, "exception")
              or else Starts_With_Word (Current, "begin")
              or else Current = "private"
              or else (Starts_With_Word (Current, "when")
                       and then not (Is_Opener (PC)
                                     and then (Ends_With_Word (PC, "is")
                                               or else Ends_With_Word (PC, "exception")
                                               or else Ends_With_Word (PC, "select"))))
            then
               Result := Result - Indent_Width;
               --  "end case" closes both the last alternative and the case
               if Starts_With_Word (Current, "end")
                 and then Starts_With_Word (Trim_Left (Current (Current'First + 3 .. Current'Last)), "case")
                 and then not Is_Opener (PC)
               then
                  Result := Result - Indent_Width;
               end if;
            end if;
         end if;
      end;
      return Natural (Integer'Max (0, Result));
   end Indentation_For;

   --  Point stays on the same text, or moves to the indentation if it was
   --  in the leading blanks
   procedure Indent_Line_To (B : in out Buffer; Target : Natural) is
      Len        : constant Natural := Length (B);
      S          : constant Natural := Line_Start (B, B.Point);
      E          : Natural := S;
      In_Leading : Boolean;
      Offset     : Natural;
   begin
      while E < Len and then Char_At (B, E) in ' ' | L1.HT loop
         E := E + 1;
      end loop;
      In_Leading := B.Point <= E;
      Offset := (if In_Leading then 0 else B.Point - E);

      --  Leave a correct indentation alone, so TAB does not mark the buffer
      --  modified
      if Slice (B, S, E) /= (1 .. Target => ' ') then
         Delete (B, S, E);
         B.Point := S;
         Insert (B, (1 .. Target => ' '));
      end if;
      B.Point := S + Target + Offset;
   end Indent_Line_To;

   procedure Indent_Line (B : in out Buffer) is
   begin
      Indent_Line_To (B, Indentation_For (B, Line_Start (B, B.Point)));
   end Indent_Line;

end Ada_Indent;
