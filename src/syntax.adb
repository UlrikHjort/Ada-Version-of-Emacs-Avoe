-- ***************************************************************************
--                               Avoe - Syntax
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
with Ada.Strings.Fixed;
with Mode_Defs;
with Utils;

package body Syntax is

   package L1 renames Ada.Characters.Latin_1;

   --  ANSI colour codes per face (SGR parameters); Set_Face changes them
   Codes : array (Face) of Unbounded_String :=
     (Face_Default => Null_Unbounded_String,
      Face_Keyword => To_Unbounded_String ("1;35"),
      Face_Comment => To_Unbounded_String ("32"),
      Face_String  => To_Unbounded_String ("33"),
      Face_Number  => To_Unbounded_String ("36"),
      Face_Error   => To_Unbounded_String ("31"),
      Face_Warning => To_Unbounded_String ("33"),
      Face_Status  => To_Unbounded_String ("1"),
      Face_Type    => To_Unbounded_String ("1;36"),
      Face_Paren   => To_Unbounded_String ("1;4"));

   Ada_Keywords : constant String :=
     " abort abs abstract accept access aliased all and array at begin body"
     & " case constant declare delay delta digits do else elsif end entry"
     & " exception exit for function generic goto if in interface is limited"
     & " loop mod new not null of or others out overriding package pragma"
     & " private procedure protected raise range record rem renames requeue"
     & " return reverse select separate some subtype synchronized tagged task"
     & " terminate then type until use when while with xor ";

   function Lower (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         C := Utils.To_Lower (C);
      end loop;
      return R;
   end Lower;

   --  Word lists have a blank before and after every word, so searching for
   --  " word " finds whole words only
   function Is_Ada_Keyword (Word : String) return Boolean is
     (Word'Length > 1
      and then Ada.Strings.Fixed.Index (Ada_Keywords, " " & Word & " ") > 0);

   function Mode_Name (Mode : Mode_Kind) return String is (Mode_Defs.Title (Mode));

   function Has_Highlighting (Mode : Mode_Kind) return Boolean is
      use type Mode_Defs.Highlighter_Kind;
   begin
      return Mode_Defs.Get (Mode).Highlighter /= Mode_Defs.No_Highlighting;
   end Has_Highlighting;

   --  Reset first, so that a face never inherits bold or colour from the last
   function SGR (F : Face) return String is
     (L1.ESC & "[0m"
      & (if Length (Codes (F)) = 0 then ""
         else L1.ESC & "[" & To_String (Codes (F)) & "m"));

   procedure Set_Face (Name : String; Code : String; Ok : out Boolean) is
   begin
      Ok := False;
      for C of Code loop
         if C not in '0' .. '9' | ';' then
            return;
         end if;
      end loop;
      for F in Face loop
         if Lower (Face'Image (F)) = "face_" & Lower (Name) then
            Codes (F) := To_Unbounded_String (Code);
            Ok := True;
            return;
         end if;
      end loop;
   end Set_Face;

   --  "file:line:" or "file:line:column:" at the start of a line, as GNAT,
   --  GCC and grep -n write them.  The file name may not contain blanks.
   function Parse_Location
     (Text   : String;
      File   : out Unbounded_String;
      Line   : out Natural;
      Column : out Natural) return Boolean
   is
      Colon : constant Natural := Ada.Strings.Fixed.Index (Text, ":");
      I     : Natural;

      procedure Number (Value : out Natural; Count : out Natural) is
      begin
         Value := 0;
         Count := 0;
         while I <= Text'Last and then Text (I) in '0' .. '9' loop
            Value := Natural'Min (Value * 10 + (Character'Pos (Text (I)) - 48), 10_000_000);
            Count := Count + 1;
            I := I + 1;
         end loop;
      end Number;

      Value, Count : Natural;
   begin
      File := Null_Unbounded_String;
      Line := 0;
      Column := 0;
      if Colon <= Text'First then
         return False;
      end if;
      for C of Text (Text'First .. Colon - 1) loop
         if C = ' ' or else C = L1.HT then
            return False;
         end if;
      end loop;

      I := Colon + 1;
      Number (Value, Count);
      if Count = 0 or else I > Text'Last or else Text (I) /= ':' then
         return False;
      end if;
      Line := Value;
      I := I + 1;
      Number (Value, Count);
      if Count > 0 and then I <= Text'Last and then Text (I) = ':' then
         Column := Value;
      end if;
      File := To_Unbounded_String (Text (Text'First .. Colon - 1));
      return True;
   end Parse_Location;

   procedure Highlight_Ada (B : Buffer; Start, Stop : Natural; Faces : in out Face_Array) is
      P    : Natural := Start;
      Prev : Character := ' ';  --  Last significant character

      function Is_Word_Char (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');
   begin
      while P < Stop loop
         declare
            C : constant Character := Char_At (B, P);
         begin
            if C = '-' and then P + 1 < Stop and then Char_At (B, P + 1) = '-' then
               Faces (P .. Stop - 1) := (others => Face_Comment);
               return;

            elsif C = '"' then
               declare
                  Q : Natural := P + 1;
               begin
                  while Q < Stop loop
                     if Char_At (B, Q) /= '"' then
                        Q := Q + 1;
                     elsif Q + 1 < Stop and then Char_At (B, Q + 1) = '"' then
                        Q := Q + 2;
                     else
                        Q := Q + 1;
                        exit;
                     end if;
                  end loop;
                  Faces (P .. Q - 1) := (others => Face_String);
                  P := Q;
                  Prev := '"';
               end;

            elsif C = ''' then
               --  'x' is a character literal, unless it follows a name or a
               --  closing parenthesis (an attribute such as X'First)
               if P + 2 < Stop and then Char_At (B, P + 2) = '''
                 and then not Is_Word_Char (Prev) and then Prev /= ')'
               then
                  Faces (P .. P + 2) := (others => Face_String);
                  P := P + 3;
                  Prev := '"';
               else
                  P := P + 1;
                  Prev := ''';
               end if;

            elsif C in 'a' .. 'z' | 'A' .. 'Z' then
               declare
                  Q : Natural := P;
               begin
                  while Q < Stop and then Is_Word_Char (Char_At (B, Q)) loop
                     Q := Q + 1;
                  end loop;
                  --  After a tick it is an attribute ('Range, 'Access)
                  if Prev /= ''' and then Q - P <= 12
                    and then Is_Ada_Keyword (Lower (Slice (B, P, Q)))
                  then
                     Faces (P .. Q - 1) := (others => Face_Keyword);
                  end if;
                  P := Q;
                  Prev := 'a';
               end;

            elsif C in '0' .. '9' then
               declare
                  Q : Natural := P;
               begin
                  --  Also based literals (16#FF#) and decimals, but stop before
                  --  a range such as 1 .. 10
                  while Q < Stop
                    and then (Is_Word_Char (Char_At (B, Q)) or else Char_At (B, Q) in '#' | '.')
                  loop
                     exit when Char_At (B, Q) = '.' and then Q + 1 < Stop
                       and then Char_At (B, Q + 1) = '.';
                     Q := Q + 1;
                  end loop;
                  Faces (P .. Q - 1) := (others => Face_Number);
                  P := Q;
                  Prev := '0';
               end;

            else
               if C /= ' ' and then C /= L1.HT then
                  Prev := C;
               end if;
               P := P + 1;
            end if;
         end;
      end loop;
   end Highlight_Ada;

   procedure Highlight_Compilation
     (B : Buffer; Start, Stop : Natural; Faces : in out Face_Array)
   is
      Text   : constant String := Lower (Slice (B, Start, Stop));
      File   : Unbounded_String;
      Line   : Natural;
      Column : Natural;
      F      : Face := Face_Default;
   begin
      --  A located message is an error unless it says it is a warning,
      --  style or info message
      if Parse_Location (Text, File, Line, Column) then
         F := (if Ada.Strings.Fixed.Index (Text, "warning") > 0
                 or else Ada.Strings.Fixed.Index (Text, "style") > 0
                 or else Ada.Strings.Fixed.Index (Text, "info:") > 0
               then Face_Warning else Face_Error);
      elsif Utils.Starts_With (Text, "compilation ") then
         F := Face_Status;
      end if;
      if F /= Face_Default then
         Faces (Start .. Stop - 1) := (others => F);
      end if;
   end Highlight_Compilation;

   function Matches (B : Buffer; P : Natural; S : String) return Boolean is
   begin
      if S'Length = 0 or else P + S'Length > Length (B) then
         return False;
      end if;
      for I in S'Range loop
         if Char_At (B, P + (I - S'First)) /= S (I) then
            return False;
         end if;
      end loop;
      return True;
   end Matches;

   --  Is Pos inside a block comment?  Only looks a limited distance back
   --  and does not know about strings, which is good enough for display.
   function In_Block_Comment (B : Buffer; Pos : Natural; Open, Close : String) return Boolean is
      Limit : constant Integer := Integer'Max (0, Pos - 5_000);
   begin
      if Open = Close then
         --  Same delimiter both ways (Python """): count them
         declare
            Count : Natural := 0;
            P     : Integer := Limit;
         begin
            while P <= Pos - Open'Length loop
               if Matches (B, P, Open) then
                  Count := Count + 1;
                  P := P + Open'Length;
               else
                  P := P + 1;
               end if;
            end loop;
            return Count mod 2 = 1;
         end;
      end if;
      for P in reverse Limit .. Pos - 1 loop
         if Matches (B, P, Close) and then P + Close'Length <= Pos then
            return False;
         elsif Matches (B, P, Open) and then P + Open'Length <= Pos then
            return True;
         end if;
      end loop;
      return False;
   end In_Block_Comment;

   --  Highlighting driven by a mode definition from a script
   procedure Highlight_Generic
     (B     : Buffer;
      Start : Natural;
      Stop  : Natural;
      D     : Mode_Defs.Mode_Def;
      Faces : in out Face_Array)
   is
      Line_Comment : constant String := To_String (D.Line_Comment);
      Open         : constant String := To_String (D.Block_Comment_Start);
      Close        : constant String := To_String (D.Block_Comment_End);
      Keywords     : constant String := To_String (D.Keywords);
      Types        : constant String := To_String (D.Types);
      Has_Blocks   : constant Boolean := Open /= "" and then Close /= "";
      P            : Natural := Start;

      function Word_Char (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');

      procedure Comment_Until_Close (From : Natural) is
         Q : Natural := From;
      begin
         while Q < Stop and then not Matches (B, Q, Close) loop
            Q := Q + 1;
         end loop;
         if Q < Stop then
            Q := Natural'Min (Q + Close'Length, Stop);
         end if;
         Faces (P .. Q - 1) := (others => Face_Comment);
         P := Q;
      end Comment_Until_Close;

   begin
      if Has_Blocks and then In_Block_Comment (B, Start, Open, Close) then
         Comment_Until_Close (Start);
      end if;

      while P < Stop loop
         declare
            C : constant Character := Char_At (B, P);
         begin
            if Has_Blocks and then Matches (B, P, Open) then
               Comment_Until_Close (P + Open'Length);

            elsif Line_Comment /= "" and then Matches (B, P, Line_Comment)
              --  # only starts a comment at the start of a word, so that $#
              --  and ${#x} in shell scripts are not comments
              and then (Line_Comment /= "#" or else P = Start
                        or else Char_At (B, P - 1) in ' ' | L1.HT | ';')
            then
               Faces (P .. Stop - 1) := (others => Face_Comment);
               return;

            elsif C = '"' or else (C = ''' and then D.Backslash_Escapes) then
               declare
                  Q : Natural := P + 1;
               begin
                  while Q < Stop loop
                     if D.Backslash_Escapes and then Char_At (B, Q) = '\' then
                        Q := Q + 2;
                     elsif Char_At (B, Q) = C then
                        Q := Q + 1;
                        exit;
                     else
                        Q := Q + 1;
                     end if;
                  end loop;
                  Q := Natural'Min (Q, Stop);
                  Faces (P .. Q - 1) := (others => Face_String);
                  P := Q;
               end;

            elsif C in 'a' .. 'z' | 'A' .. 'Z' | '_' then
               declare
                  Q : Natural := P;
               begin
                  while Q < Stop and then Word_Char (Char_At (B, Q)) loop
                     Q := Q + 1;
                  end loop;
                  declare
                     W : constant String :=
                       " " & (if D.Case_Sensitive then Slice (B, P, Q)
                              else Lower (Slice (B, P, Q))) & " ";
                  begin
                     if Ada.Strings.Fixed.Index (Keywords, W) > 0 then
                        Faces (P .. Q - 1) := (others => Face_Keyword);
                     elsif Ada.Strings.Fixed.Index (Types, W) > 0 then
                        Faces (P .. Q - 1) := (others => Face_Type);
                     end if;
                  end;
                  P := Q;
               end;

            elsif C in '0' .. '9' then
               declare
                  Q : Natural := P;
               begin
                  while Q < Stop
                    and then (Word_Char (Char_At (B, Q)) or else Char_At (B, Q) = '.')
                  loop
                     Q := Q + 1;
                  end loop;
                  Faces (P .. Q - 1) := (others => Face_Number);
                  P := Q;
               end;

            else
               P := P + 1;
            end if;
         end;
      end loop;
   end Highlight_Generic;

   --  Lines are highlighted one at a time as they are drawn; only block
   --  comments make it look further back
   procedure Highlight_Line (B : Buffer; Start, Stop : Natural; Faces : out Face_Array) is
      D : constant Mode_Defs.Mode_Def := Mode_Defs.Get (B.Mode);
   begin
      Faces := (others => Face_Default);
      case D.Highlighter is
         when Mode_Defs.Ada_Highlighting =>
            Highlight_Ada (B, Start, Stop, Faces);
         when Mode_Defs.Compilation_Highlighting =>
            Highlight_Compilation (B, Start, Stop, Faces);
         when Mode_Defs.Generic_Highlighting =>
            Highlight_Generic (B, Start, Stop, D, Faces);
         when Mode_Defs.No_Highlighting =>
            null;
      end case;
   end Highlight_Line;

end Syntax;
