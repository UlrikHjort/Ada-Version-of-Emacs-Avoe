-- ***************************************************************************
--                               Avoe - Display
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
with Buffers;               use Buffers;
with Syntax;
with Terminal;
with Utils;                 use Utils;

package body Display is

   use Windows;

   package L1 renames Ada.Characters.Latin_1;

   ESC : constant Character := L1.ESC;

   Replacement : constant String :=
     Character'Val (16#EF#) & Character'Val (16#BF#) & Character'Val (16#BD#);

   Max_Rows : constant := 1024;

   Rows : Positive := 24;
   Cols : Positive := 80;

   type Frame_Array is array (Positive range <>) of Unbounded_String;

   Frame       : Frame_Array (1 .. Max_Rows);
   Frame_Valid : Boolean := False;

   Highlight_On   : Boolean := False;
   Highlight_From : Natural := 0;
   Highlight_To   : Natural := 0;

   procedure Update_Size is
      R, C : Positive;
   begin
      Terminal.Get_Size (R, C);
      Rows := Integer'Max (3, Integer'Min (R, Max_Rows));
      Cols := C;
      if Windows.Count > 0 then
         Windows.Layout (Rows - 1);
      end if;
      Frame_Valid := False;
   end Update_Size;

   procedure Invalidate is
   begin
      Frame_Valid := False;
   end Invalidate;

   function Screen_Rows return Positive is (Rows);
   function Screen_Cols return Positive is (Cols);

   procedure Set_Highlight (From, To : Natural) is
   begin
      Highlight_On := True;
      Highlight_From := From;
      Highlight_To := To;
   end Set_Highlight;

   procedure Clear_Highlight is
   begin
      Highlight_On := False;
   end Clear_Highlight;

   procedure Recenter_At (W : Window_Access; Point : Natural) is
      B : Buffer renames W.Buf.all;
      P : Natural := Line_Start (B, Point);
   begin
      for I in 1 .. W.Height / 2 loop
         exit when P = 0;
         P := Line_Start (B, P - 1);
      end loop;
      W.Top := P;
   end Recenter_At;

   procedure Recenter (W : Window_Access) is
   begin
      Recenter_At (W, Point_Of (W));
   end Recenter;

   --  Render the line starting at Start.  Next is the start of the
   --  following line; At_End is True if this is the last line.
   procedure Render_Line
     (B        : Buffer;
      Start    : Natural;
      Left_Col : Natural;
      Width    : Positive;
      HL_From  : Natural;
      HL_To    : Natural;
      Paren_1  : Integer;   --  Positions of a matching bracket pair, or -1
      Paren_2  : Integer;
      Line     : out Unbounded_String;
      Next     : out Natural;
      At_End   : out Boolean)
   is
      Len        : constant Natural := Length (B);
      Cell_Start : array (1 .. Width) of Positive := (others => 1);
      Used       : Natural := 0;
      Col        : Natural := 0;
      Q          : Natural := Start;
      In_HL      : Boolean := False;
      Hidden_Left     : Boolean := False;
      Truncated_Right : Boolean := False;

      Stop      : constant Natural := Line_End (B, Start);
      Use_Faces : constant Boolean :=
        Syntax.Has_Highlighting (B.Mode)
        and then Stop - Start <= Syntax.Max_Highlight_Length;
      Faces     : Syntax.Face_Array (Start .. (if Use_Faces then Stop - 1 else Start - 1));
      Cur_Face  : Syntax.Face := Syntax.Face_Default;
      Styled    : Boolean := False;

      use type Syntax.Face;

      procedure Emit_Cell (Text : String) is
      begin
         if Col < Left_Col then
            Hidden_Left := True;
         elsif Used < Width then
            Used := Used + 1;
            Cell_Start (Used) := Length (Line) + 1;
            Append (Line, Text);
         else
            Truncated_Right := True;
         end if;
         Col := Col + 1;
      end Emit_Cell;

   begin
      Line := Null_Unbounded_String;
      if Use_Faces then
         Syntax.Highlight_Line (B, Start, Stop, Faces);
      end if;

      while Q < Len and then not Truncated_Right loop
         declare
            C    : constant Character := Char_At (B, Q);
            Code : constant Natural := Character'Pos (C);
            L    : Positive;
         begin
            exit when C = L1.LF;

            declare
               F : constant Syntax.Face :=
                 (if Q = Paren_1 or else Q = Paren_2 then Syntax.Face_Paren
                  elsif Use_Faces then Faces (Q)
                  else Syntax.Face_Default);
               H : constant Boolean := Q >= HL_From and then Q < HL_To;
            begin
               if F /= Cur_Face or else H /= In_HL then
                  Cur_Face := F;
                  In_HL := H;
                  Append (Line, Syntax.SGR (F) & (if H then ESC & "[7m" else ""));
                  Styled := True;
               end if;
            end;

            if C = L1.HT then
               loop
                  Emit_Cell (" ");
                  exit when Col mod Tab_Width = 0;
               end loop;
               Q := Q + 1;
            elsif Code < 32 then
               Emit_Cell ("^");
               Emit_Cell ((1 => Character'Val (Code + 64)));
               Q := Q + 1;
            elsif Code = 127 then
               Emit_Cell ("^");
               Emit_Cell ("?");
               Q := Q + 1;
            elsif Code < 128 then
               Emit_Cell ((1 => C));
               Q := Q + 1;
            else
               L := Char_Length (B, Q);
               if L = 1 then
                  Emit_Cell (Replacement);
               else
                  Emit_Cell (Slice (B, Q, Q + L));
               end if;
               Q := Q + L;
            end if;
         end;
      end loop;

      if Q < Len and then Char_At (B, Q) /= L1.LF then
         Q := Line_End (B, Q);
      end if;

      if Truncated_Right then
         Line := To_Unbounded_String
           (Ada.Strings.Unbounded.Slice (Line, 1, Cell_Start (Width) - 1) & "$");
      end if;
      if Hidden_Left and then Used >= 1 then
         if Used >= 2 then
            Line := To_Unbounded_String
              ("$" & Ada.Strings.Unbounded.Slice
                       (Line, Cell_Start (2), Length (Line)));
         else
            Line := To_Unbounded_String ("$");
         end if;
      end if;

      if Styled then
         Append (Line, ESC & "[0m");
      end if;
      if Used < Width then
         Append (Line, ESC & "[K");
      end if;

      if Q >= Len then
         Next := Len;
         At_End := True;
      else
         Next := Q + 1;
         At_End := False;
      end if;
   end Render_Line;

   procedure Render_Window
     (W          : Window_Access;
      Is_Current : Boolean;
      First_Row  : Positive;
      New_Frame  : in out Frame_Array;
      Cursor_Row : out Positive;
      Cursor_Col : out Positive)
   is
      B           : Buffer renames W.Buf.all;
      Height      : constant Positive := W.Height;
      Len         : constant Natural := Length (B);
      Point       : constant Natural := Point_Of (W);
      HL_From     : Natural := 0;
      HL_To       : Natural := 0;
      Paren_1     : Integer := -1;
      Paren_2     : Integer := -1;
      P           : Natural;
      Done        : Boolean := False;
      End_Visible : Boolean := False;
      Point_Col   : Natural;
      Top_Line    : Positive := 1;
      Margin      : Natural := 0;    --  Cells used by line numbers
      Text_Cols   : Positive := Cols;
   begin
      if Is_Current and then Highlight_On then
         HL_From := Highlight_From;
         HL_To := Highlight_To;
      end if;
      if Is_Current then
         Brackets.Pair_At (B, Point, Paren_1, Paren_2);
      end if;

      --  Keep the window start at a line start
      W.Top := Line_Start (B, Natural'Min (W.Top, Len));

      --  Vertical scrolling
      if Point < W.Top then
         Recenter_At (W, Point);
      else
         declare
            Q : Natural := W.Top;
            N : Natural := 0;
            E : Natural;
         begin
            loop
               E := Line_End (B, Q);
               exit when Point <= E;
               N := N + 1;
               if N >= Height then
                  Recenter_At (W, Point);
                  exit;
               end if;
               Q := E + 1;
            end loop;
         end;
      end if;

      --  Line numbers in the left margin, as in Emacs: as wide as the
      --  largest number that can be visible in the window, then a space
      if B.Line_Numbers then
         Top_Line := Line_Number (B, W.Top);
         Margin := Img (Top_Line + Height - 1)'Length + 1;
         if Cols - Margin < 2 then
            Margin := 0;
         end if;
      end if;
      Text_Cols := Cols - Margin;

      --  Horizontal scrolling
      Point_Col := Column_Of (B, Point);
      if (W.Left_Col > 0 and then Point_Col <= W.Left_Col)
        or else Point_Col >= W.Left_Col + Text_Cols - 1
      then
         W.Left_Col := (if Point_Col < Text_Cols - 1 then 0 else Point_Col - Text_Cols / 2);
      end if;
      Cursor_Col := Margin + Point_Col - W.Left_Col + 1;
      Cursor_Row := First_Row;

      --  Text rows
      P := W.Top;
      for R in 1 .. Height loop
         if Done then
            New_Frame (First_Row + R - 1) := To_Unbounded_String (ESC & "[K");
         else
            declare
               Line   : Unbounded_String;
               Next   : Natural;
               At_End : Boolean;
            begin
               Render_Line (B, P, W.Left_Col, Text_Cols, HL_From, HL_To, Paren_1, Paren_2,
                            Line, Next, At_End);
               if Point >= P and then Point <= (if At_End then Len else Next - 1) then
                  Cursor_Row := First_Row + R - 1;
               end if;
               if Margin > 0 then
                  --  Grey numbers; the cursor's line in bold
                  declare
                     Number : constant String := Img (Top_Line + R - 1);
                     Blanks : constant String (1 .. Margin - 1 - Number'Length) := (others => ' ');
                  begin
                     Line := To_Unbounded_String
                       (ESC & (if Cursor_Row = First_Row + R - 1 then "[1m" else "[90m")
                        & Blanks & Number & ESC & "[0m ") & Line;
                  end;
               end if;
               New_Frame (First_Row + R - 1) := Line;
               if At_End then
                  Done := True;
                  End_Visible := True;
               end if;
               P := Next;
            end;
         end if;
      end loop;

      --  Mode line
      declare
         Status : constant String :=
           (if B.Read_Only then (if B.Modified then "%*" else "%%")
            else (if B.Modified then "**" else "--"));
         Where  : constant String :=
           (if W.Top = 0 and then End_Visible then "All"
            elsif W.Top = 0 then "Top"
            elsif End_Visible then "Bot"
            else Img (Integer (Long_Long_Integer (W.Top) * 100
                               / Long_Long_Integer (Len))) & "%");
         Text   : constant String :=
           (if Is_Current then "-" else " ") & Status & "- "
           & Pad (To_String (B.Name), 20) & " " & Pad (Where, 4)
           & " (" & Img (Line_Number (B, Point)) & "," & Img (Point_Col) & ")"
           & "   [" & Syntax.Mode_Name (B.Mode) & "]";
      begin
         New_Frame (First_Row + Height) := To_Unbounded_String
           (ESC & "[7m" & Head_Cells (Pad (Text, Cols), Cols) & ESC & "[0m");
      end;
   end Render_Window;

   procedure Render (Echo : String; Echo_Cursor : Integer := -1) is
      New_Frame  : Frame_Array (1 .. Rows);
      Row        : Positive := 1;
      Cursor_Row : Positive := 1;
      Cursor_Col : Positive := 1;
   begin
      for I in 1 .. Windows.Count loop
         declare
            W  : constant Window_Access := Windows.Get (I);
            CR : Positive;
            CC : Positive;
         begin
            exit when Row + W.Height > Rows - 1;
            Render_Window (W, I = Windows.Current_Index, Row, New_Frame, CR, CC);
            if I = Windows.Current_Index then
               Cursor_Row := CR;
               Cursor_Col := CC;
            end if;
            Row := Row + W.Height + 1;
         end;
      end loop;
      for R in Row .. Rows - 1 loop
         New_Frame (R) := To_Unbounded_String (ESC & "[K");
      end loop;

      --  Echo area (never write the last column of the last row)
      declare
         Room  : constant Natural := Cols - 1;
         Shown : Unbounded_String;
         Col   : Natural;
      begin
         if Cell_Count (Echo) <= Room then
            Shown := To_Unbounded_String (Echo);
            Col := Integer'Max (Echo_Cursor, 0);
         elsif Echo_Cursor >= Room then
            Shown := To_Unbounded_String
              (Tail_Cells (Head_Cells (Echo, Echo_Cursor), Room - 1));
            Col := Cell_Count (To_String (Shown));
         else
            Shown := To_Unbounded_String (Head_Cells (Echo, Room));
            Col := Integer'Max (Echo_Cursor, 0);
         end if;
         New_Frame (Rows) := Shown & ESC & "[K";
         if Echo_Cursor >= 0 then
            Cursor_Row := Rows;
            Cursor_Col := Col + 1;
         end if;
      end;

      --  Emit changed rows
      Terminal.Put (ESC & "[?25l");
      for R in 1 .. Rows loop
         if not Frame_Valid or else Frame (R) /= New_Frame (R) then
            Terminal.Put (ESC & "[" & Img (R) & ";1H" & To_String (New_Frame (R)));
            Frame (R) := New_Frame (R);
         end if;
      end loop;
      Frame_Valid := True;
      Terminal.Put (ESC & "[" & Img (Cursor_Row) & ";" & Img (Cursor_Col) & "H"
                    & ESC & "[?25h");
      Terminal.Flush;
   end Render;

end Display;
