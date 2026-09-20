-- ***************************************************************************
--                            Avoe - Edit_Commands
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Brackets;
with Buffer_List;
with Buffers;    use Buffers;
with Commands;   use Commands;
with Mode_Defs;
with String_Vectors;
with Display;
with Keys;       use Keys;
with Kill_Ring;
with Minibuffer; use Minibuffer;
with Utils;      use Utils;
with Windows;

package body Edit_Commands is

   package L1 renames Ada.Characters.Latin_1;

   Goal_Column : Natural := 0;

   function Cur return Buffer_Access renames Windows.Current_Buffer;

   -------------------------------------------------------------------------
   --  Motion
   -------------------------------------------------------------------------

   procedure Forward_Char is
      B : Buffer renames Cur.all;
   begin
      if B.Point < Length (B) then
         B.Point := Next_Pos (B, B.Point);
      else
         Message ("End of buffer");
      end if;
   end Forward_Char;

   procedure Backward_Char is
      B : Buffer renames Cur.all;
   begin
      if B.Point > 0 then
         B.Point := Prev_Pos (B, B.Point);
      else
         Message ("Beginning of buffer");
      end if;
   end Backward_Char;

   procedure Start_Vertical_Motion is
   begin
      if Last_Class /= Class_Vertical then
         Goal_Column := Column_Of (Cur.all, Cur.Point);
      end if;
      This_Class := Class_Vertical;
   end Start_Vertical_Motion;

   procedure Next_Line is
      B : Buffer renames Cur.all;
      E : constant Natural := Line_End (B, B.Point);
   begin
      Start_Vertical_Motion;
      if E >= Length (B) then
         Message ("End of buffer");
      else
         B.Point := Pos_At_Column (B, E + 1, Goal_Column);
      end if;
   end Next_Line;

   procedure Previous_Line is
      B : Buffer renames Cur.all;
      S : constant Natural := Line_Start (B, B.Point);
   begin
      Start_Vertical_Motion;
      if S = 0 then
         Message ("Beginning of buffer");
      else
         B.Point := Pos_At_Column (B, Line_Start (B, S - 1), Goal_Column);
      end if;
   end Previous_Line;

   procedure Beginning_Of_Line is
   begin
      Cur.Point := Line_Start (Cur.all, Cur.Point);
   end Beginning_Of_Line;

   procedure End_Of_Line is
   begin
      Cur.Point := Line_End (Cur.all, Cur.Point);
   end End_Of_Line;

   procedure Push_Mark is
   begin
      Cur.Mark := Cur.Point;
      Cur.Mark_Set := True;
   end Push_Mark;

   procedure Beginning_Of_Buffer is
   begin
      Push_Mark;
      Message ("Mark set");
      Cur.Point := 0;
   end Beginning_Of_Buffer;

   procedure End_Of_Buffer is
   begin
      Push_Mark;
      Message ("Mark set");
      Cur.Point := Length (Cur.all);
   end End_Of_Buffer;

   function Is_Word_Char (B : Buffer; P : Natural) return Boolean is
      C : constant Character := Char_At (B, P);
   begin
      return C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' or else Character'Pos (C) >= 128;
   end Is_Word_Char;

   function Forward_Word_End (B : Buffer; From : Natural) return Natural is
      Len : constant Natural := Length (B);
      P   : Natural := From;
   begin
      while P < Len and then not Is_Word_Char (B, P) loop
         P := P + 1;
      end loop;
      while P < Len and then Is_Word_Char (B, P) loop
         P := P + 1;
      end loop;
      return P;
   end Forward_Word_End;

   function Backward_Word_Start (B : Buffer; From : Natural) return Natural is
      P : Natural := From;
   begin
      while P > 0 and then not Is_Word_Char (B, P - 1) loop
         P := P - 1;
      end loop;
      while P > 0 and then Is_Word_Char (B, P - 1) loop
         P := P - 1;
      end loop;
      return P;
   end Backward_Word_Start;

   procedure Forward_Word is
   begin
      Cur.Point := Forward_Word_End (Cur.all, Cur.Point);
   end Forward_Word;

   procedure Backward_Word is
   begin
      Cur.Point := Backward_Word_Start (Cur.all, Cur.Point);
   end Backward_Word;

   function Scroll_Amount return Positive is
     (Integer'Max (1, Windows.Current.Height - 2));

   procedure Scroll_Up is
      W   : constant Windows.Window_Access := Windows.Current;
      B   : Buffer renames W.Buf.all;
      Len : constant Natural := Length (B);
      Top : constant Natural := Line_Start (B, Natural'Min (W.Top, Len));
      P   : Natural := Top;
      E   : Natural;
   begin
      for I in 1 .. Scroll_Amount loop
         E := Line_End (B, P);
         exit when E >= Len;
         P := E + 1;
      end loop;
      if P = Top then
         B.Point := Len;
         Message ("End of buffer");
         return;
      end if;
      W.Top := P;
      if B.Point < P then
         B.Point := P;
      end if;
   end Scroll_Up;

   procedure Scroll_Down is
      W   : constant Windows.Window_Access := Windows.Current;
      B   : Buffer renames W.Buf.all;
      Len : constant Natural := Length (B);
      P   : Natural := Line_Start (B, Natural'Min (W.Top, Len));
      Q   : Natural;
      E   : Natural;
   begin
      if P = 0 then
         B.Point := 0;
         Message ("Beginning of buffer");
         return;
      end if;
      for I in 1 .. Scroll_Amount loop
         exit when P = 0;
         P := Line_Start (B, P - 1);
      end loop;
      W.Top := P;

      --  Keep point inside the window: find the last visible line
      Q := P;
      for I in 1 .. W.Height - 1 loop
         E := Line_End (B, Q);
         exit when E >= Len;
         Q := E + 1;
      end loop;
      if B.Point > Line_End (B, Q) then
         B.Point := Q;
      end if;
   end Scroll_Down;

   procedure Recenter is
   begin
      Display.Recenter (Windows.Current);
      Display.Invalidate;
   end Recenter;

   procedure Goto_Line is
      Text : Unbounded_String;
      Ok   : Boolean;
      N    : Integer;
   begin
      if Arg_Given then
         N := Prefix_Arg;
      else
         Read_String ("Goto line: ", "", Text, Ok);
         if not Ok then
            return;
         end if;
         begin
            N := Integer'Value (To_String (Text));
         exception
            when Constraint_Error =>
               Message ("Please enter a line number");
               return;
         end;
      end if;
      Push_Mark;
      Cur.Point := Pos_Of_Line (Cur.all, Integer'Max (1, N));
   end Goto_Line;

   -------------------------------------------------------------------------
   --  Editing
   -------------------------------------------------------------------------

   procedure Self_Insert is
   begin
      Insert (Cur.all, Encode_UTF8 (Last_Key.Code));
      This_Class := Class_Insert;
   end Self_Insert;

   procedure Newline is
   begin
      Insert (Cur.all, (1 => L1.LF));
   end Newline;

   procedure Newline_And_Indent is
      B : Buffer renames Cur.all;
      S : constant Natural := Line_Start (B, B.Point);
      E : Natural := S;
   begin
      while E < B.Point and then Char_At (B, E) in ' ' | L1.HT loop
         E := E + 1;
      end loop;
      Insert (B, L1.LF & Slice (B, S, E));
   end Newline_And_Indent;

   procedure Open_Line is
   begin
      Insert (Cur.all, (1 => L1.LF));
      Cur.Point := Cur.Point - 1;
   end Open_Line;

   procedure Insert_Tab is
   begin
      Insert (Cur.all, (1 => L1.HT));
   end Insert_Tab;

   procedure Delete_Char is
      B : Buffer renames Cur.all;
   begin
      if B.Point < Length (B) then
         Delete (B, B.Point, Next_Pos (B, B.Point));
      else
         Message ("End of buffer");
      end if;
   end Delete_Char;

   procedure Delete_Backward_Char is
      B : Buffer renames Cur.all;
   begin
      if B.Point > 0 then
         Delete (B, Prev_Pos (B, B.Point), B.Point);
      else
         Message ("Beginning of buffer");
      end if;
   end Delete_Backward_Char;

   procedure Quoted_Insert is
      K : constant Key := Read_Key_Echo ("C-q-");
   begin
      if K.Code < Key_None then
         Insert (Cur.all, Encode_UTF8 (K.Code));
      end if;
   end Quoted_Insert;

   procedure Transpose_Chars is
      B   : Buffer renames Cur.all;
      Len : constant Natural := Length (B);
      P   : Natural := B.Point;
   begin
      if P = 0 or else Len < 2 then
         Message ("Beginning of buffer");
         return;
      end if;
      if P >= Len or else Char_At (B, P) = L1.LF then
         P := Prev_Pos (B, P);
      end if;
      if P = 0 then
         Message ("Beginning of buffer");
         return;
      end if;
      declare
         A      : constant Natural := Prev_Pos (B, P);
         C      : constant Natural := Next_Pos (B, P);
         First  : constant String := Slice (B, A, P);
         Second : constant String := Slice (B, P, C);
      begin
         Delete (B, A, C);
         B.Point := A;
         Insert (B, Second & First);
      end;
   end Transpose_Chars;

   type Case_Mode is (Upper, Lower, Capital);

   procedure Change_Word_Case (Mode : Case_Mode) is
      B     : Buffer renames Cur.all;
      S     : constant Natural := B.Point;
      E     : constant Natural := Forward_Word_End (B, S);
      Old   : constant String := Slice (B, S, E);
      New_S : String := Old;
      First : Boolean := True;
   begin
      for C of New_S loop
         case Mode is
            when Upper =>
               C := To_Upper (C);
            when Lower =>
               C := To_Lower (C);
            when Capital =>
               if C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' then
                  C := (if First then To_Upper (C) else To_Lower (C));
                  First := False;
               end if;
         end case;
      end loop;
      if New_S /= Old then
         Delete (B, S, E);
         B.Point := S;
         Insert (B, New_S);
      else
         B.Point := E;
      end if;
   end Change_Word_Case;

   procedure Upcase_Word is
   begin
      Change_Word_Case (Upper);
   end Upcase_Word;

   procedure Downcase_Word is
   begin
      Change_Word_Case (Lower);
   end Downcase_Word;

   procedure Capitalize_Word is
   begin
      Change_Word_Case (Capital);
   end Capitalize_Word;

   -------------------------------------------------------------------------
   --  Mark, region, killing and yanking
   -------------------------------------------------------------------------

   procedure Set_Mark is
   begin
      Push_Mark;
      Cur.Mark_Active := True;
      Message ("Mark set");
   end Set_Mark;

   procedure Exchange_Point_And_Mark is
      B   : Buffer renames Cur.all;
      Old : constant Natural := B.Point;
   begin
      if not B.Mark_Set then
         Message ("No mark set in this buffer");
         return;
      end if;
      B.Point := B.Mark;
      B.Mark := Old;
   end Exchange_Point_And_Mark;

   procedure Mark_Whole_Buffer is
      B : Buffer renames Cur.all;
   begin
      B.Mark := Length (B);
      B.Mark_Set := True;
      B.Point := 0;
      Message ("Mark set");
   end Mark_Whole_Buffer;

   function Get_Region (From, To : out Natural) return Boolean is
      B : Buffer renames Cur.all;
   begin
      From := Natural'Min (B.Point, B.Mark);
      To := Natural'Max (B.Point, B.Mark);
      if not B.Mark_Set then
         Message ("The mark is not set now, so there is no region");
         return False;
      end if;
      return True;
   end Get_Region;

   procedure Kill (From, To : Natural; Backward : Boolean := False) is
      Text : constant Unbounded_String := Text_Of (Cur.all, From, To);
   begin
      Delete (Cur.all, From, To);
      if Last_Class = Class_Kill then
         Kill_Ring.Append_To_Newest (Text, Before => Backward);
      else
         Kill_Ring.Push (Text);
      end if;
      This_Class := Class_Kill;
   end Kill;

   procedure Kill_Line is
      B   : Buffer renames Cur.all;
      Len : constant Natural := Length (B);
      P   : constant Natural := B.Point;
      E   : constant Natural := Line_End (B, P);
      Q   : Natural := P;
   begin
      if P >= Len then
         Message ("End of buffer");
         return;
      end if;
      while Q < E and then Char_At (B, Q) in ' ' | L1.HT loop
         Q := Q + 1;
      end loop;
      --  Only whitespace up to the end of line: kill the newline too
      if Q = E and then E < Len then
         Kill (P, E + 1);
      else
         Kill (P, E);
      end if;
   end Kill_Line;

   procedure Kill_Region is
      From, To : Natural;
   begin
      if Get_Region (From, To) then
         Kill (From, To);
      end if;
   end Kill_Region;

   procedure Copy_Region is
      From, To : Natural;
   begin
      if Get_Region (From, To) then
         Kill_Ring.Push (Text_Of (Cur.all, From, To));
         Message ("Region copied");
      end if;
   end Copy_Region;

   procedure Kill_Word is
   begin
      Kill (Cur.Point, Forward_Word_End (Cur.all, Cur.Point));
   end Kill_Word;

   procedure Backward_Kill_Word is
   begin
      Kill (Backward_Word_Start (Cur.all, Cur.Point), Cur.Point, Backward => True);
   end Backward_Kill_Word;

   procedure Yank is
   begin
      if Kill_Ring.Is_Empty then
         Message ("Kill ring is empty");
         return;
      end if;
      Push_Mark;
      Insert (Cur.all, Kill_Ring.Current);
      This_Class := Class_Yank;
   end Yank;

   procedure Yank_Pop is
      B : Buffer renames Cur.all;
   begin
      if Last_Class /= Class_Yank then
         Message ("Previous command was not a yank");
         return;
      end if;
      declare
         From : constant Natural := Natural'Min (B.Point, B.Mark);
         To   : constant Natural := Natural'Max (B.Point, B.Mark);
      begin
         Delete (B, From, To);
         B.Point := From;
         Kill_Ring.Rotate;
         B.Mark := From;
         Insert (B, Kill_Ring.Current);
      end;
      This_Class := Class_Yank;
   end Yank_Pop;

   -------------------------------------------------------------------------
   --  Undo and information
   -------------------------------------------------------------------------

   procedure Undo is
      Ok : Boolean;
   begin
      Undo_Step (Cur.all, Continue => Last_Class = Class_Undo, Ok => Ok);
      if not Ok then
         Message ("No further undo information");
      end if;
      This_Class := Class_Undo;
   end Undo;

   procedure What_Cursor_Position is
      B     : Buffer renames Cur.all;
      Len   : constant Natural := Length (B);
      P     : constant Natural := B.Point;
      Pct   : constant Integer :=
        (if Len = 0 then 0
         else Integer (Long_Long_Integer (P) * 100 / Long_Long_Integer (Len)));
      Where : constant String :=
        "point=" & Img (P + 1) & " of " & Img (Len + 1) & " (" & Img (Pct)
        & "%)  line=" & Img (Line_Number (B, P))
        & "  column=" & Img (Column_Of (B, P));
   begin
      if P >= Len then
         Message (Where);
         return;
      end if;
      declare
         Code  : constant Natural := Code_Point_At (B, P);
         Shown : constant String :=
           (if Code < 32 then "^" & Character'Val (Code + 64)
            elsif Code = 127 then "^?"
            else Slice (B, P, Next_Pos (B, P)));
      begin
         Message ("Char: " & Shown & " (" & Img (Code) & ", #x" & Hex (Code) & ")  "
                  & Where);
      end;
   end What_Cursor_Position;

   procedure Keyboard_Quit is
   begin
      Cur.Mark_Active := False;
      Message ("Quit");
   end Keyboard_Quit;

   -------------------------------------------------------------------------

   -------------------------------------------------------------------------
   --  Brackets
   -------------------------------------------------------------------------

   function Is_Blank (C : Character) return Boolean is (C in ' ' | L1.HT | L1.LF | L1.CR);

   procedure Forward_Sexp is
      B : Buffer renames Cur.all;
   begin
      while B.Point < Length (B) and then Is_Blank (Char_At (B, B.Point)) loop
         B.Point := B.Point + 1;
      end loop;
      if B.Point < Length (B) and then Brackets.Is_Open (Char_At (B, B.Point)) then
         declare
            M : constant Integer := Brackets.Matching (B, B.Point);
         begin
            if M < 0 then
               Message ("Unbalanced brackets");
            else
               B.Point := M + 1;
            end if;
         end;
      else
         Forward_Word;
      end if;
   end Forward_Sexp;

   procedure Backward_Sexp is
      B : Buffer renames Cur.all;
   begin
      while B.Point > 0 and then Is_Blank (Char_At (B, B.Point - 1)) loop
         B.Point := B.Point - 1;
      end loop;
      if B.Point > 0 and then Brackets.Is_Close (Char_At (B, B.Point - 1)) then
         declare
            M : constant Integer := Brackets.Matching (B, B.Point - 1);
         begin
            if M < 0 then
               Message ("Unbalanced brackets");
            else
               B.Point := M;
            end if;
         end;
      else
         Backward_Word;
      end if;
   end Backward_Sexp;

   -------------------------------------------------------------------------
   --  Comments
   -------------------------------------------------------------------------

   function Looking_At (B : Buffer; Pos : Natural; Text : String) return Boolean is
     (Pos + Text'Length <= Length (B) and then Slice (B, Pos, Pos + Text'Length) = Text);

   function First_Non_Blank (B : Buffer; Line : Natural) return Natural is
      E : constant Natural := Line_End (B, Line);
      P : Natural := Line;
   begin
      while P < E and then Char_At (B, P) in ' ' | L1.HT loop
         P := P + 1;
      end loop;
      return P;
   end First_Non_Blank;

   --  Comment or uncomment the current line, or the lines of the active
   --  region, using the mode's line comment marker
   procedure Comment_Dwim is
      B      : Buffer renames Cur.all;
      Marker : constant String := To_String (Mode_Defs.Get (B.Mode).Line_Comment);
      Region : constant Boolean :=
        B.Mark_Set and then B.Mark_Active
        and then Line_Start (B, B.Mark) /= Line_Start (B, B.Point);
      From   : constant Natural := (if Region then Natural'Min (B.Mark, B.Point) else B.Point);
      To     : Natural := (if Region then Natural'Max (B.Mark, B.Point) else B.Point);
      First  : Natural;
      Last   : Natural;
      S      : Natural;
      Indent : Natural := Natural'Last;
      Any    : Boolean := False;
      All_Commented : Boolean := True;
      Saved  : aliased Natural := B.Point;
   begin
      if Marker = "" then
         Message ("No comment syntax is defined for " & Mode_Defs.Title (B.Mode) & " mode");
         return;
      end if;
      --  A region ending at the start of a line does not include that line
      if Region and then To = Line_Start (B, To) then
         To := To - 1;
      end if;
      First := Line_Start (B, From);
      Last := Line_Start (B, To);

      S := First;
      loop
         declare
            T : constant Natural := First_Non_Blank (B, S);
         begin
            if T < Line_End (B, S) then
               Any := True;
               Indent := Natural'Min (Indent, Column_Of (B, T));
               if not Looking_At (B, T, Marker) then
                  All_Commented := False;
               end if;
            end if;
         end;
         exit when S >= Last;
         S := Line_End (B, S) + 1;
      end loop;

      if not Any then
         Insert (B, Marker & " ");
         return;
      end if;

      --  Saved is a local variable: it must be unregistered however this
      --  ends (a read-only buffer raises on the first change), or later
      --  changes would write through a dangling pointer
      Register_Marker (B, Saved'Unchecked_Access);
      begin
         S := First;
         loop
            declare
               T : constant Natural := First_Non_Blank (B, S);
            begin
               if T < Line_End (B, S) then
                  if All_Commented then
                     Delete (B, T, T + Marker'Length);
                     if T < Length (B) and then Char_At (B, T) = ' ' then
                        Delete (B, T, T + 1);
                     end if;
                  else
                     B.Point := Pos_At_Column (B, S, Indent);
                     Insert (B, Marker & " ");
                  end if;
               end if;
            end;
            exit when S >= Last or else Line_End (B, S) >= Length (B);
            S := Line_End (B, S) + 1;
            --  Last moves as text is inserted or deleted on earlier lines
            Last := Line_Start (B, Natural'Max (S, Last));
         end loop;
      exception
         when others =>
            Unregister_Marker (B, Saved'Unchecked_Access);
            raise;
      end;
      Unregister_Marker (B, Saved'Unchecked_Access);
      B.Point := Natural'Min (Saved, Length (B));
   end Comment_Dwim;

   -------------------------------------------------------------------------
   --  Filling
   -------------------------------------------------------------------------

   procedure Fill_Paragraph is
      B      : Buffer renames Cur.all;
      Marker : constant String := To_String (Mode_Defs.Get (B.Mode).Line_Comment);

      --  Indentation, plus a comment marker and the blanks after it
      function Prefix_Of (S : Natural) return String is
         E : constant Natural := Line_End (B, S);
         P : Natural := First_Non_Blank (B, S);
      begin
         if Marker /= "" and then P + Marker'Length <= E and then Looking_At (B, P, Marker) then
            P := P + Marker'Length;
            while P < E and then Char_At (B, P) in ' ' | L1.HT loop
               P := P + 1;
            end loop;
         end if;
         return Slice (B, S, P);
      end Prefix_Of;

      Line   : constant Natural := Line_Start (B, B.Point);
      Prefix : constant String := Prefix_Of (Line);

      function In_Paragraph (S : Natural) return Boolean is
        (Line_End (B, S) - S > Prefix'Length and then Prefix_Of (S) = Prefix);

      First  : Natural := Line;
      Last   : Natural := Line;
      Words  : String_Vectors.Vector;
      Before : Natural := 0;   --  Word characters before point
   begin
      if not In_Paragraph (Line) then
         return;
      end if;
      while First > 0 and then In_Paragraph (Line_Start (B, First - 1)) loop
         First := Line_Start (B, First - 1);
      end loop;
      while Line_End (B, Last) < Length (B) and then In_Paragraph (Line_End (B, Last) + 1) loop
         Last := Line_End (B, Last) + 1;
      end loop;

      --  Collect the words
      declare
         S : Natural := First;
      begin
         loop
            declare
               E : constant Natural := Line_End (B, S);
               P : Natural := S + Prefix'Length;
               W : Natural;
            begin
               loop
                  while P < E and then Char_At (B, P) in ' ' | L1.HT loop
                     P := P + 1;
                  end loop;
                  exit when P >= E;
                  W := P;
                  while W < E and then Char_At (B, W) not in ' ' | L1.HT loop
                     W := W + 1;
                  end loop;
                  Words.Append (Slice (B, P, W));
                  if B.Point > P then
                     Before := Before + Natural'Min (W, B.Point) - P;
                  end if;
                  P := W;
               end loop;
            end;
            exit when S >= Last;
            S := Line_End (B, S) + 1;
         end loop;
      end;

      declare
         Stop     : constant Natural := Line_End (B, Last);
         Result   : Unbounded_String;
         Width    : Natural := 0;
         Has_Word : Boolean := False;
         Written  : Natural := 0;
         Target   : Integer := -1;
      begin
         for W of Words loop
            if not Has_Word then
               Append (Result, Prefix);
               Width := Cell_Count (Prefix);
            elsif Width + 1 + Cell_Count (W) > Fill_Column then
               Append (Result, L1.LF & Prefix);
               Width := Cell_Count (Prefix);
            else
               Append (Result, ' ');
               Width := Width + 1;
            end if;
            if Target < 0 and then Written + W'Length >= Before then
               Target := Length (Result) + (Before - Written);
            end if;
            Append (Result, W);
            Width := Width + Cell_Count (W);
            Written := Written + W'Length;
            Has_Word := True;
         end loop;

         if To_String (Result) /= Slice (B, First, Stop) then
            Delete (B, First, Stop);
            B.Point := First;
            Insert (B, Result);
         end if;
         B.Point := First + (if Target >= 0 then Target else Length (Result));
      end;
   end Fill_Paragraph;

   procedure Set_Fill_Column is
   begin
      Fill_Column := (if Arg_Given then Prefix_Arg
                      else Positive'Max (1, Column_Of (Cur.all, Cur.Point)));
      Message ("Fill column set to" & Positive'Image (Fill_Column));
   end Set_Fill_Column;

   -------------------------------------------------------------------------
   --  Whitespace, words, lines and paragraphs
   -------------------------------------------------------------------------

   function Is_Space (B : Buffer; P : Natural) return Boolean is
     (Char_At (B, P) in ' ' | L1.HT);

   procedure Back_To_Indentation is
   begin
      Cur.Point := First_Non_Blank (Cur.all, Line_Start (Cur.all, Cur.Point));
   end Back_To_Indentation;

   --  The blanks around point: [From, To)
   procedure Blanks_Around (From, To : out Natural) is
      B : Buffer renames Cur.all;
   begin
      From := B.Point;
      To := B.Point;
      while From > 0 and then Is_Space (B, From - 1) loop
         From := From - 1;
      end loop;
      while To < Length (B) and then Is_Space (B, To) loop
         To := To + 1;
      end loop;
   end Blanks_Around;

   procedure Delete_Horizontal_Space is
      From, To : Natural;
   begin
      Blanks_Around (From, To);
      Delete (Cur.all, From, To);
      Cur.Point := From;
   end Delete_Horizontal_Space;

   procedure Just_One_Space is
      B        : Buffer renames Cur.all;
      From, To : Natural;
   begin
      Blanks_Around (From, To);
      if To - From = 1 and then Char_At (B, From) = ' ' then
         B.Point := To;
         return;
      end if;
      Delete (B, From, To);
      B.Point := From;
      Insert (B, " ");
   end Just_One_Space;

   --  Join this line to the previous one, leaving one space between them
   --  (none next to a bracket)
   procedure Delete_Indentation is
      B : Buffer renames Cur.all;
      S : constant Natural := Line_Start (B, B.Point);
   begin
      if S = 0 then
         Message ("Beginning of buffer");
         return;
      end if;
      Delete (B, S - 1, First_Non_Blank (B, S));
      B.Point := S - 1;
      Delete_Horizontal_Space;
      if B.Point > 0 and then B.Point < Length (B)
        and then Char_At (B, B.Point) not in ')' | ']' | '}' | L1.LF
        and then Char_At (B, B.Point - 1) not in '(' | '[' | '{' | L1.LF
      then
         Insert (B, " ");
         B.Point := B.Point - 1;
      end if;
   end Delete_Indentation;

   --  Kill up to and including the next occurrence of a character typed
   --  by the user (with C-u N: the Nth occurrence)
   procedure Zap_To_Char is
      B     : Buffer renames Cur.all;
      K     : constant Key := Read_Key_Echo ("Zap to char: ");
      Count : constant Positive := Prefix_Arg;
      P     : Natural := B.Point;
   begin
      if K.Meta or else K.Code >= Key_None or else K.Code = Ctl_G then
         Message ("Quit");
         return;
      end if;
      declare
         Target : constant String :=
           (if K.Code = Ret then (1 => L1.LF) else Encode_UTF8 (K.Code));
      begin
         for I in 1 .. Count loop
            while P < Length (B)
              and then (Char_At (B, P) /= Target (Target'First)
                        or else not Looking_At (B, P, Target))
            loop
               P := P + 1;
            end loop;
            if P >= Length (B) then
               Message ("Search failed: " & (if K.Code = Ret then "RET" else Target));
               return;
            end if;
            P := P + Target'Length;
         end loop;
         Kill (B.Point, P);
      end;
   end Zap_To_Char;

   --  Swap the words before and after point (inside a word: that word and
   --  the next one); point ends after both
   procedure Transpose_Words is
      B     : Buffer renames Cur.all;
      P     : constant Natural := B.Point;
      Start : constant Natural :=
        (if P > 0 and then P < Length (B) and then Is_Word_Char (B, P)
           and then Is_Word_Char (B, P - 1)
         then Forward_Word_End (B, P) else P);
      E2    : constant Natural := Forward_Word_End (B, Start);
      S2    : constant Natural := Backward_Word_Start (B, E2);
      S1    : constant Natural := Backward_Word_Start (B, S2);
      E1    : constant Natural := Forward_Word_End (B, S1);
   begin
      if S1 = S2 or else E2 = S2 or else E1 > S2 then
         Message ("Don't have two words to transpose");
         return;
      end if;
      declare
         Text : constant String := Slice (B, S2, E2) & Slice (B, E1, S2) & Slice (B, S1, E1);
      begin
         Delete (B, S1, E2);
         B.Point := S1;
         Insert (B, Text);
      end;
   end Transpose_Words;

   --  Swap this line with the previous one; point moves to the next line
   procedure Transpose_Lines is
      B : Buffer renames Cur.all;
      S : constant Natural := Line_Start (B, B.Point);
   begin
      if S = 0 then
         Message ("Beginning of buffer");
         return;
      end if;
      declare
         P    : constant Natural := Line_Start (B, S - 1);
         E    : constant Natural := Line_End (B, S);
         Text : constant String := Slice (B, S, E) & L1.LF & Slice (B, P, S - 1);
      begin
         Delete (B, P, E);
         B.Point := P;
         Insert (B, Text);
         if B.Point < Length (B) then
            B.Point := B.Point + 1;
         else
            Insert (B, (1 => L1.LF));
         end if;
      end;
   end Transpose_Lines;

   procedure Change_Region_Case (Mode : Case_Mode) is
      B        : Buffer renames Cur.all;
      From, To : Natural;
   begin
      if not Get_Region (From, To) then
         return;
      end if;
      declare
         Old       : constant String := Slice (B, From, To);
         New_S     : String := Old;
         Old_Point : constant Natural := B.Point;
         Old_Mark  : constant Natural := B.Mark;
      begin
         for C of New_S loop
            C := (if Mode = Upper then To_Upper (C) else To_Lower (C));
         end loop;
         if New_S /= Old then
            Delete (B, From, To);
            B.Point := From;
            Insert (B, New_S);
            B.Point := Old_Point;
            B.Mark := Old_Mark;
         end if;
      end;
   end Change_Region_Case;

   procedure Upcase_Region is
   begin
      Change_Region_Case (Upper);
   end Upcase_Region;

   procedure Downcase_Region is
   begin
      Change_Region_Case (Lower);
   end Downcase_Region;

   function Is_Blank_Line (B : Buffer; S : Natural) return Boolean is
     (First_Non_Blank (B, S) >= Line_End (B, S));

   --  Paragraphs are separated by blank lines
   procedure Forward_Paragraph is
      B : Buffer renames Cur.all;
      S : Natural := Line_Start (B, B.Point);
   begin
      while Line_End (B, S) < Length (B) and then Is_Blank_Line (B, S) loop
         S := Line_End (B, S) + 1;
      end loop;
      while Line_End (B, S) < Length (B) and then not Is_Blank_Line (B, S) loop
         S := Line_End (B, S) + 1;
      end loop;
      B.Point := (if Is_Blank_Line (B, S) then S else Line_End (B, S));
   end Forward_Paragraph;

   procedure Backward_Paragraph is
      B : Buffer renames Cur.all;
      S : Natural := Line_Start (B, B.Point);
   begin
      if B.Point = S and then S > 0 then
         S := Line_Start (B, S - 1);
      end if;
      while S > 0 and then Is_Blank_Line (B, S) loop
         S := Line_Start (B, S - 1);
      end loop;
      while S > 0 and then not Is_Blank_Line (B, S) loop
         S := Line_Start (B, S - 1);
      end loop;
      B.Point := S;
   end Backward_Paragraph;

   --  Lines, words and characters in the active region, or in the buffer
   procedure Count_Words_Region is
      B      : Buffer renames Cur.all;
      Region : constant Boolean := B.Mark_Set and then B.Mark_Active;
      From   : constant Natural := (if Region then Natural'Min (B.Point, B.Mark) else 0);
      To     : constant Natural := (if Region then Natural'Max (B.Point, B.Mark) else Length (B));
      Lines, Words, Chars : Natural := 0;

      function Count (N : Natural; What : String) return String is
        (Img (N) & " " & What & (if N = 1 then "" else "s"));
   begin
      for P in From .. Integer (To) - 1 loop
         declare
            C : constant Character := Char_At (B, P);
         begin
            if C = L1.LF then
               Lines := Lines + 1;
            end if;
            if Is_Word_Char (B, P) and then (P = From or else not Is_Word_Char (B, P - 1)) then
               Words := Words + 1;
            end if;
            if Character'Pos (C) not in 16#80# .. 16#BF# then
               Chars := Chars + 1;
            end if;
         end;
      end loop;
      if To > From and then Char_At (B, To - 1) /= L1.LF then
         Lines := Lines + 1;
      end if;
      Message ((if Region then "Region" else "Buffer") & " has " & Count (Lines, "line") & ", "
               & Count (Words, "word") & " and " & Count (Chars, "character"));
   end Count_Words_Region;

   -------------------------------------------------------------------------
   --  Dynamic abbreviations: M-/ completes the word before point from
   --  words in the buffers, nearest first; repeating it tries the next one
   -------------------------------------------------------------------------

   Max_Candidates     : constant := 1000;
   Dabbrev_Candidates : String_Vectors.Vector;
   Dabbrev_Index      : Natural := 0;       --  Candidate in the buffer, 0: the prefix
   Dabbrev_Start      : Natural := 0;       --  Where the word being expanded starts
   Dabbrev_Prefix     : Unbounded_String;
   Dabbrev_Buffer     : Buffer_Access := null;

   --  Add the words in [From, To) of B that are longer than Prefix and
   --  start with it, in order or in reverse order
   procedure Collect_Words (B : Buffer; From, To : Natural; Prefix : String; Reversed : Boolean) is
      Found : String_Vectors.Vector;
      P     : Natural := From;

      procedure Add (Word : String) is
      begin
         if Natural (Dabbrev_Candidates.Length) < Max_Candidates
           and then not Dabbrev_Candidates.Contains (Word)
         then
            Dabbrev_Candidates.Append (Word);
         end if;
      end Add;
   begin
      while P < To loop
         if Is_Word_Char (B, P) and then (P = 0 or else not Is_Word_Char (B, P - 1)) then
            declare
               E : constant Natural := Forward_Word_End (B, P);
            begin
               if E - P > Prefix'Length and then E <= To
                 and then Char_At (B, P) = Prefix (Prefix'First)
                 and then Looking_At (B, P, Prefix)
               then
                  Found.Append (Slice (B, P, E));
               end if;
               P := E;
            end;
         else
            P := P + 1;
         end if;
      end loop;
      if Reversed then
         for I in reverse Found.First_Index .. Found.Last_Index loop
            Add (Found (I));
         end loop;
      else
         for Word of Found loop
            Add (Word);
         end loop;
      end if;
   end Collect_Words;

   procedure Dabbrev_Expand is
      B          : Buffer renames Cur.all;
      Continuing : constant Boolean :=
        To_String (Last_Command) = "dabbrev_expand"
        and then Dabbrev_Buffer = Cur
        and then B.Point >= Dabbrev_Start
        and then Dabbrev_Index <= Natural (Dabbrev_Candidates.Length)
        and then Slice (B, Dabbrev_Start, B.Point) =
          (if Dabbrev_Index = 0 then To_String (Dabbrev_Prefix)
           else Dabbrev_Candidates (Dabbrev_Index));
   begin
      if not Continuing then
         if B.Point = 0 or else not Is_Word_Char (B, B.Point - 1) then
            Message ("No word before point to expand");
            return;
         end if;
         Dabbrev_Start := Backward_Word_Start (B, B.Point);
         Dabbrev_Prefix := To_Unbounded_String (Slice (B, Dabbrev_Start, B.Point));
         Dabbrev_Candidates.Clear;
         Dabbrev_Index := 0;
         Dabbrev_Buffer := Cur;
         declare
            Prefix : constant String := To_String (Dabbrev_Prefix);
         begin
            Collect_Words (B, 0, Dabbrev_Start, Prefix, Reversed => True);
            Collect_Words (B, B.Point, Length (B), Prefix, Reversed => False);
            for I in 1 .. Buffer_List.Count loop
               if Buffer_List.Get (I) /= Cur then
                  Collect_Words (Buffer_List.Get (I).all, 0, Length (Buffer_List.Get (I).all),
                                 Prefix, Reversed => False);
               end if;
            end loop;
         end;
      end if;

      declare
         Next        : constant Positive := Dabbrev_Index + 1;
         Have_Next   : constant Boolean := Next <= Natural (Dabbrev_Candidates.Length);
         Replacement : constant String :=
           (if Have_Next then Dabbrev_Candidates (Next) else To_String (Dabbrev_Prefix));
      begin
         if Slice (B, Dabbrev_Start, B.Point) /= Replacement then
            Delete (B, Dabbrev_Start, B.Point);
            B.Point := Dabbrev_Start;
            Insert (B, Replacement);
         end if;
         if Have_Next then
            Dabbrev_Index := Next;
         else
            Dabbrev_Index := 0;
            Message ((if Dabbrev_Candidates.Is_Empty then "No dynamic expansion for "
                      else "No further dynamic expansions for ")
                     & To_String (Dabbrev_Prefix));
         end if;
      end;
   end Dabbrev_Expand;

   -------------------------------------------------------------------------
   --  Line numbers in the left margin
   -------------------------------------------------------------------------

   procedure Display_Line_Numbers_Mode is
      B : Buffer renames Cur.all;
   begin
      B.Line_Numbers := not B.Line_Numbers;
      Message ("Display-Line-Numbers mode "
               & (if B.Line_Numbers then "enabled" else "disabled") & " in current buffer");
   end Display_Line_Numbers_Mode;

   procedure Global_Display_Line_Numbers_Mode is
      Enabled : constant Boolean := not Line_Numbers_Default;
   begin
      Line_Numbers_Default := Enabled;
      for I in 1 .. Buffer_List.Count loop
         Buffer_List.Get (I).Line_Numbers := Enabled;
      end loop;
      Message ("Global Display-Line-Numbers mode " & (if Enabled then "enabled" else "disabled"));
   end Global_Display_Line_Numbers_Mode;

   procedure Register_All is
   begin
      Register ("forward_sexp", Forward_Sexp'Access, Repeatable => True);
      Register ("backward_sexp", Backward_Sexp'Access, Repeatable => True);
      Register ("comment_dwim", Comment_Dwim'Access);
      Register ("fill_paragraph", Fill_Paragraph'Access);
      Register ("set_fill_column", Set_Fill_Column'Access);
      Register ("forward_char", Forward_Char'Access, Repeatable => True);
      Register ("backward_char", Backward_Char'Access, Repeatable => True);
      Register ("next_line", Next_Line'Access, Repeatable => True);
      Register ("previous_line", Previous_Line'Access, Repeatable => True);
      Register ("forward_word", Forward_Word'Access, Repeatable => True);
      Register ("backward_word", Backward_Word'Access, Repeatable => True);
      Register ("beginning_of_line", Beginning_Of_Line'Access);
      Register ("end_of_line", End_Of_Line'Access);
      Register ("beginning_of_buffer", Beginning_Of_Buffer'Access);
      Register ("end_of_buffer", End_Of_Buffer'Access);
      Register ("scroll_up", Scroll_Up'Access);
      Register ("scroll_down", Scroll_Down'Access);
      Register ("recenter", Recenter'Access);
      Register ("goto_line", Goto_Line'Access);

      Register ("self_insert", Self_Insert'Access, Repeatable => True);
      Register ("newline", Newline'Access, Repeatable => True);
      Register ("newline_and_indent", Newline_And_Indent'Access, Repeatable => True);
      Register ("open_line", Open_Line'Access, Repeatable => True);
      Register ("insert_tab", Insert_Tab'Access, Repeatable => True);
      Register ("delete_char", Delete_Char'Access, Repeatable => True);
      Register ("delete_backward_char", Delete_Backward_Char'Access, Repeatable => True);
      Register ("quoted_insert", Quoted_Insert'Access, Repeatable => True);
      Register ("transpose_chars", Transpose_Chars'Access, Repeatable => True);
      Register ("upcase_word", Upcase_Word'Access, Repeatable => True);
      Register ("downcase_word", Downcase_Word'Access, Repeatable => True);
      Register ("capitalize_word", Capitalize_Word'Access, Repeatable => True);

      Register ("set_mark", Set_Mark'Access);
      Register ("exchange_point_and_mark", Exchange_Point_And_Mark'Access);
      Register ("mark_whole_buffer", Mark_Whole_Buffer'Access);
      Register ("kill_line", Kill_Line'Access, Repeatable => True);
      Register ("kill_region", Kill_Region'Access);
      Register ("copy_region", Copy_Region'Access);
      Register ("kill_word", Kill_Word'Access, Repeatable => True);
      Register ("backward_kill_word", Backward_Kill_Word'Access, Repeatable => True);
      Register ("yank", Yank'Access);
      Register ("yank_pop", Yank_Pop'Access);

      Register ("undo", Undo'Access, Repeatable => True);
      Register ("what_cursor_position", What_Cursor_Position'Access);
      Register ("keyboard_quit", Keyboard_Quit'Access);

      Register ("back_to_indentation", Back_To_Indentation'Access);
      Register ("delete_horizontal_space", Delete_Horizontal_Space'Access);
      Register ("just_one_space", Just_One_Space'Access);
      Register ("delete_indentation", Delete_Indentation'Access, Repeatable => True);
      Register ("zap_to_char", Zap_To_Char'Access);
      Register ("transpose_words", Transpose_Words'Access, Repeatable => True);
      Register ("transpose_lines", Transpose_Lines'Access, Repeatable => True);
      Register ("upcase_region", Upcase_Region'Access);
      Register ("downcase_region", Downcase_Region'Access);
      Register ("forward_paragraph", Forward_Paragraph'Access, Repeatable => True);
      Register ("backward_paragraph", Backward_Paragraph'Access, Repeatable => True);
      Register ("count_words_region", Count_Words_Region'Access);
      Register ("dabbrev_expand", Dabbrev_Expand'Access);
      Register ("display_line_numbers_mode", Display_Line_Numbers_Mode'Access);
      Register ("global_display_line_numbers_mode", Global_Display_Line_Numbers_Mode'Access);
   end Register_All;

end Edit_Commands;
