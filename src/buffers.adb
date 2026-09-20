-- ***************************************************************************
--                               Avoe - Buffers
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
with Ada.Exceptions;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Directories;
with File_IO;
with Utils;

package body Buffers is

   package L1 renames Ada.Characters.Latin_1;
   package SIO renames Ada.Streams.Stream_IO;

   Chunk_Size : constant := 65_536;

   procedure Invalidate_Line_Cache (B : in out Buffer; Pos : Natural) is
   begin
      if Pos < B.Line_Cache_Pos then
         B.Line_Cache_Pos := 0;
         B.Line_Cache_Line := 1;
      end if;
   end Invalidate_Line_Cache;

   function Length (B : Buffer) return Natural is (B.Text.Length);

   function Char_At (B : Buffer; Pos : Natural) return Character is
     (B.Text.Element (Pos));

   function Slice (B : Buffer; From, To : Natural) return String is
     (B.Text.Slice (From, To));

   function Text_Of (B : Buffer; From, To : Natural) return Unbounded_String is
      Result : Unbounded_String;
      P      : Natural := From;
      Q      : Natural;
   begin
      while P < To loop
         Q := Natural'Min (To, P + Chunk_Size);
         Append (Result, B.Text.Slice (P, Q));
         P := Q;
      end loop;
      return Result;
   end Text_Of;

   -------------------------------------------------------------------------
   --  Undo recording
   -------------------------------------------------------------------------

   --  Forget the oldest undo groups once the history is over its limits,
   --  down to three quarters of them so that trimming is not repeated on
   --  every change.  The newest group is always kept; while it alone is
   --  too big, trimming is only tried again after another quarter.
   procedure Trim_Undo (B : in out Buffer) is
      Cut : Natural := 0;
   begin
      if (Natural (B.Undo_List.Length) <= Max_Undo_Records
          and then B.Undo_Bytes <= Max_Undo_Bytes)
        or else Natural (B.Undo_List.Length) < B.Undo_Trim_At
      then
         return;
      end if;
      loop
         exit when Natural (B.Undo_List.Length) - Cut <= Max_Undo_Records - Max_Undo_Records / 4
           and then B.Undo_Bytes <= Max_Undo_Bytes - Max_Undo_Bytes / 4;
         declare
            I     : Natural := Cut + 1;
            Bytes : Natural := 0;
         begin
            while I <= B.Undo_List.Last_Index and then B.Undo_List (I).Kind /= Boundary loop
               Bytes := Bytes + Length (B.Undo_List (I).Text);
               I := I + 1;
            end loop;
            exit when I >= B.Undo_List.Last_Index;
            Cut := I;
            B.Undo_Bytes := B.Undo_Bytes - Bytes;
         end;
      end loop;
      if Cut > 0 then
         B.Undo_List.Delete_First (Ada.Containers.Count_Type (Cut));
         B.Undo_Next := (if B.Undo_Next > Cut then B.Undo_Next - Cut else 0);
      end if;
      B.Undo_Trim_At :=
        (if Natural (B.Undo_List.Length) > Max_Undo_Records or else B.Undo_Bytes > Max_Undo_Bytes
         then Natural (B.Undo_List.Length) + Max_Undo_Records / 4
         else 0);
   end Trim_Undo;

   procedure Record_Insert (B : in out Buffer; Pos, Len : Natural) is
   begin
      if not B.Undo_List.Is_Empty then
         declare
            Last : Undo_Record := B.Undo_List.Last_Element;
         begin
            if Last.Kind = Inserted and then Last.Pos + Last.Len = Pos then
               Last.Len := Last.Len + Len;
               B.Undo_List.Replace_Element (B.Undo_List.Last_Index, Last);
               return;
            end if;
         end;
      end if;
      B.Undo_List.Append
        ((Kind         => Inserted,
          Pos          => Pos,
          Len          => Len,
          Text         => Null_Unbounded_String,
          Point_Before => B.Point,
          Was_Modified => B.Modified));
   end Record_Insert;

   procedure Record_Delete (B : in out Buffer; From, To : Natural) is
   begin
      B.Undo_List.Append
        ((Kind         => Deleted,
          Pos          => From,
          Len          => To - From,
          Text         => Text_Of (B, From, To),
          Point_Before => B.Point,
          Was_Modified => B.Modified));
      B.Undo_Bytes := B.Undo_Bytes + (To - From);
   end Record_Delete;

   procedure Add_Undo_Boundary (B : in out Buffer) is
   begin
      if B.Undo_Enabled
        and then not B.Undo_List.Is_Empty
        and then B.Undo_List.Last_Element.Kind /= Boundary
      then
         B.Undo_List.Append ((Kind => Boundary, others => <>));
         --  Only trim between groups: Undo_Step walks the list by index
         --  while it appends to it
         Trim_Undo (B);
      end if;
   end Add_Undo_Boundary;

   procedure Undo_Step (B : in out Buffer; Continue : Boolean; Ok : out Boolean) is
      I : Natural;
      R : Undo_Record;
   begin
      if not Continue then
         --  The inverse changes form a group of their own, so that a later
         --  undo undoes just this undo
         Add_Undo_Boundary (B);
         B.Undo_Next := B.Undo_List.Last_Index;
      end if;
      I := Natural'Min (B.Undo_Next, B.Undo_List.Last_Index);

      while I >= 1 and then B.Undo_List.Element (I).Kind = Boundary loop
         I := I - 1;
      end loop;
      if I = 0 then
         Ok := False;
         return;
      end if;

      if B.Read_Only then
         raise Read_Only_Error;
      end if;

      --  Apply the group newest first.  The inverse changes are appended
      --  to the list, which leaves indices below I untouched.
      while I >= 1 and then B.Undo_List.Element (I).Kind /= Boundary loop
         R := B.Undo_List.Element (I);
         case R.Kind is
            when Inserted =>
               Delete (B, R.Pos, R.Pos + R.Len);
               B.Point := R.Pos;
            when Deleted =>
               B.Point := R.Pos;
               Insert (B, R.Text);
               B.Point := Natural'Min (R.Point_Before, Length (B));
            when Boundary =>
               null;
         end case;
         B.Modified := R.Was_Modified;
         I := I - 1;
      end loop;

      B.Undo_Next := I;
      Ok := True;
   end Undo_Step;

   -------------------------------------------------------------------------
   --  Changing text
   -------------------------------------------------------------------------

   procedure Insert (B : in out Buffer; Text : String) is
      P : constant Natural := B.Point;
      N : constant Natural := Text'Length;
   begin
      if N = 0 then
         return;
      end if;
      if B.Read_Only then
         raise Read_Only_Error;
      end if;
      if B.Undo_Enabled then
         Record_Insert (B, P, N);
      end if;
      B.Text.Insert (P, Text);
      if B.Mark > P then
         B.Mark := B.Mark + N;
      end if;
      for M of B.Markers loop
         if M.all > P then
            M.all := M.all + N;
         end if;
      end loop;
      B.Point := P + N;
      B.Modified := True;
      B.Change_Tick := B.Change_Tick + 1;
      B.Mark_Active := False;
      Invalidate_Line_Cache (B, P);
   end Insert;

   procedure Insert (B : in out Buffer; Text : Unbounded_String) is
      Len : constant Natural := Length (Text);
      I   : Positive := 1;
      J   : Natural;
   begin
      while I <= Len loop
         J := Natural'Min (Len, I + Chunk_Size - 1);
         Insert (B, Ada.Strings.Unbounded.Slice (Text, I, J));
         I := J + 1;
      end loop;
   end Insert;

   procedure Delete (B : in out Buffer; From, To : Natural) is
      N : constant Natural := To - From;

      procedure Adjust (P : in out Natural) is
      begin
         if P >= To then
            P := P - N;
         elsif P > From then
            P := From;
         end if;
      end Adjust;
   begin
      if N = 0 then
         return;
      end if;
      if B.Read_Only then
         raise Read_Only_Error;
      end if;
      if B.Undo_Enabled then
         Record_Delete (B, From, To);
      end if;
      B.Text.Delete (From, To);
      Adjust (B.Point);
      Adjust (B.Mark);
      for M of B.Markers loop
         Adjust (M.all);
      end loop;
      B.Modified := True;
      B.Change_Tick := B.Change_Tick + 1;
      B.Mark_Active := False;
      Invalidate_Line_Cache (B, From);
   end Delete;

   procedure Erase (B : in out Buffer) is
   begin
      B.Text.Clear;
      B.Point := 0;
      B.Mark := 0;
      B.Mark_Set := False;
      for M of B.Markers loop
         M.all := 0;
      end loop;
      B.Undo_List.Clear;
      B.Undo_Next := 0;
      B.Undo_Bytes := 0;
      B.Undo_Trim_At := 0;
      B.Line_Cache_Pos := 0;
      B.Line_Cache_Line := 1;
      B.Modified := False;
   end Erase;

   procedure Register_Marker (B : in out Buffer; M : Marker_Access) is
   begin
      B.Markers.Append (M);
   end Register_Marker;

   procedure Unregister_Marker (B : in out Buffer; M : Marker_Access) is
      I : constant Natural := B.Markers.Find_Index (M);
   begin
      if I /= Marker_Vectors.No_Index then
         B.Markers.Delete (I);
      end if;
   end Unregister_Marker;

   -------------------------------------------------------------------------
   --  UTF-8, lines and columns
   -------------------------------------------------------------------------

   function Char_Length (B : Buffer; Pos : Natural) return Positive is
      Len   : constant Natural := Length (B);
      First : constant Natural := Character'Pos (Char_At (B, Pos));
      Need  : Natural;
   begin
      case First is
         when 16#C2# .. 16#DF# => Need := 1;
         when 16#E0# .. 16#EF# => Need := 2;
         when 16#F0# .. 16#F4# => Need := 3;
         when others           => return 1;
      end case;
      if Pos + Need >= Len then
         return 1;
      end if;
      for I in 1 .. Need loop
         if not Utils.Is_Continuation (Char_At (B, Pos + I)) then
            return 1;
         end if;
      end loop;
      return Need + 1;
   end Char_Length;

   function Next_Pos (B : Buffer; Pos : Natural) return Natural is
     (if Pos >= Length (B) then Pos else Pos + Char_Length (B, Pos));

   function Prev_Pos (B : Buffer; Pos : Natural) return Natural is
      Q : Natural;
   begin
      if Pos = 0 then
         return 0;
      end if;
      Q := Pos - 1;
      for I in 1 .. 3 loop
         exit when Q = 0 or else not Utils.Is_Continuation (Char_At (B, Q));
         Q := Q - 1;
      end loop;
      if Q + Char_Length (B, Q) = Pos then
         return Q;
      else
         return Pos - 1;
      end if;
   end Prev_Pos;

   function Code_Point_At (B : Buffer; Pos : Natural) return Natural is
      L    : constant Positive := Char_Length (B, Pos);
      Byte : constant Natural := Character'Pos (Char_At (B, Pos));
      Code : Natural;
   begin
      case L is
         when 1      => return Byte;
         when 2      => Code := Byte - 16#C0#;
         when 3      => Code := Byte - 16#E0#;
         when others => Code := Byte - 16#F0#;
      end case;
      for I in 1 .. L - 1 loop
         Code := Code * 64 + (Character'Pos (Char_At (B, Pos + I)) - 16#80#);
      end loop;
      return Code;
   end Code_Point_At;

   function Line_Start (B : Buffer; Pos : Natural) return Natural is
      P : Natural := Pos;
   begin
      while P > 0 and then Char_At (B, P - 1) /= L1.LF loop
         P := P - 1;
      end loop;
      return P;
   end Line_Start;

   function Line_End (B : Buffer; Pos : Natural) return Natural is
      Len : constant Natural := Length (B);
      P   : Natural := Pos;
   begin
      while P < Len and then Char_At (B, P) /= L1.LF loop
         P := P + 1;
      end loop;
      return P;
   end Line_End;

   function Glyph_Width (B : Buffer; Pos, Col : Natural) return Positive is
      C : constant Character := Char_At (B, Pos);
   begin
      if C = L1.HT then
         return Tab_Width - Col mod Tab_Width;
      elsif Character'Pos (C) < 32 or else Character'Pos (C) = 127 then
         return 2;  --  Shown as ^X
      else
         return 1;
      end if;
   end Glyph_Width;

   function Column_Of (B : Buffer; Pos : Natural) return Natural is
      Q   : Natural := Line_Start (B, Pos);
      Col : Natural := 0;
   begin
      while Q < Pos loop
         Col := Col + Glyph_Width (B, Q, Col);
         Q := Next_Pos (B, Q);
      end loop;
      return Col;
   end Column_Of;

   function Pos_At_Column (B : Buffer; Start, Column : Natural) return Natural is
      Len : constant Natural := Length (B);
      Q   : Natural := Start;
      Col : Natural := 0;
      W   : Positive;
   begin
      while Q < Len and then Char_At (B, Q) /= L1.LF loop
         W := Glyph_Width (B, Q, Col);
         exit when Col + W > Column;
         Col := Col + W;
         Q := Next_Pos (B, Q);
      end loop;
      return Q;
   end Pos_At_Column;

   function Line_Number (B : in out Buffer; Pos : Natural) return Positive is
      Line : Natural := B.Line_Cache_Line;
   begin
      if Pos >= B.Line_Cache_Pos then
         for P in B.Line_Cache_Pos .. Pos - 1 loop
            if Char_At (B, P) = L1.LF then
               Line := Line + 1;
            end if;
         end loop;
      else
         for P in Pos .. B.Line_Cache_Pos - 1 loop
            if Char_At (B, P) = L1.LF then
               Line := Line - 1;
            end if;
         end loop;
      end if;
      B.Line_Cache_Pos := Pos;
      B.Line_Cache_Line := Line;
      return Line;
   end Line_Number;

   function Pos_Of_Line (B : Buffer; Line : Positive) return Natural is
      Len     : constant Natural := Length (B);
      P       : Natural := 0;
      Current : Positive := 1;
   begin
      while Current < Line and then P < Len loop
         if Char_At (B, P) = L1.LF then
            Current := Current + 1;
         end if;
         P := P + 1;
      end loop;
      return P;
   end Pos_Of_Line;

   -------------------------------------------------------------------------
   --  Searching
   -------------------------------------------------------------------------

   function Matches_At
     (B : Buffer; Pattern : String; Pos : Natural; Fold : Boolean) return Boolean
   is
   begin
      for I in Pattern'Range loop
         declare
            C : constant Character := Char_At (B, Pos + (I - Pattern'First));
            P : constant Character := Pattern (I);
         begin
            if C /= P
              and then not (Fold and then Utils.To_Lower (C) = Utils.To_Lower (P))
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Matches_At;

   function Search_Forward
     (B : Buffer; Pattern : String; From : Integer; Fold : Boolean) return Integer
   is
      Last : constant Integer := Length (B) - Pattern'Length;
   begin
      for P in Integer'Max (0, From) .. Last loop
         if Matches_At (B, Pattern, P, Fold) then
            return P;
         end if;
      end loop;
      return -1;
   end Search_Forward;

   function Search_Backward
     (B : Buffer; Pattern : String; From : Integer; Fold : Boolean) return Integer
   is
      Last : constant Integer := Integer'Min (From, Length (B) - Pattern'Length);
   begin
      for P in reverse 0 .. Last loop
         if Matches_At (B, Pattern, P, Fold) then
            return P;
         end if;
      end loop;
      return -1;
   end Search_Backward;

   -------------------------------------------------------------------------
   --  Files
   -------------------------------------------------------------------------

   procedure Remember_Disk_State (B : in out Buffer) is
      I : constant File_IO.File_Info := File_IO.Info (To_String (B.File_Name));
   begin
      B.Disk_Mtime := (if I.Exists then I.Mtime else -1);
      B.Disk_Size := (if I.Exists then I.Size else -1);
   end Remember_Disk_State;

   function Changed_On_Disk (B : Buffer) return Boolean is
   begin
      if Length (B.File_Name) = 0 or else B.Disk_Mtime < 0 then
         return False;
      end if;
      declare
         I : constant File_IO.File_Info := File_IO.Info (To_String (B.File_Name));
      begin
         return I.Exists and then (I.Mtime /= B.Disk_Mtime or else I.Size /= B.Disk_Size);
      end;
   end Changed_On_Disk;

   procedure Reset (B : in out Buffer; File_Name : String) is
   begin
      Erase (B);
      B.Read_Only := False;
      B.File_Name := To_Unbounded_String (File_Name);
      B.Backup_Made := False;
      B.Disk_Mtime := -1;
      B.Disk_Size := -1;
   end Reset;

   procedure Load
     (B         : in out Buffer;
      File_Name : String;
      Message   : out Unbounded_String;
      Success   : out Boolean)
   is
      use type Ada.Directories.File_Kind;
      F     : SIO.File_Type;
      Chunk : Stream_Element_Array (1 .. Chunk_Size);
      Last  : Stream_Element_Offset;
      Saved : constant Boolean := B.Undo_Enabled;
   begin
      Success := False;

      if not Ada.Directories.Exists (File_Name) then
         Reset (B, File_Name);
         Message := To_Unbounded_String ("(New file)");
         Success := True;
         return;
      end if;

      if Ada.Directories.Kind (File_Name) /= Ada.Directories.Ordinary_File then
         Message := To_Unbounded_String (File_Name & " is not a regular file");
         return;
      end if;

      begin
         SIO.Open (F, SIO.In_File, File_Name);
      exception
         when others =>
            Message := To_Unbounded_String ("Cannot open " & File_Name);
            return;
      end;

      Reset (B, File_Name);
      B.Undo_Enabled := False;
      while not SIO.End_Of_File (F) loop
         SIO.Read (F, Chunk, Last);
         declare
            S : String (1 .. Natural (Last));
         begin
            for I in S'Range loop
               S (I) := Character'Val (Chunk (Stream_Element_Offset (I)));
            end loop;
            B.Text.Insert (B.Text.Length, S);
         end;
      end loop;
      SIO.Close (F);
      B.Undo_Enabled := Saved;
      Remember_Disk_State (B);
      B.Auto_Save_Tick := B.Change_Tick;
      Message := Null_Unbounded_String;
      Success := True;
   exception
      when E : others =>
         B.Undo_Enabled := Saved;
         if SIO.Is_Open (F) then
            SIO.Close (F);
         end if;
         Message := To_Unbounded_String
           ("Error reading " & File_Name & ": "
            & Ada.Exceptions.Exception_Message (E));
   end Load;

   --  Write the whole buffer to Path (raises on failure)
   procedure Write_Contents (B : Buffer; Path : String) is
      Len : constant Natural := Length (B);
      F   : SIO.File_Type;
      Pos : Natural := 0;
   begin
      SIO.Create (F, SIO.Out_File, Path);
      while Pos < Len loop
         declare
            To   : constant Natural := Natural'Min (Len, Pos + Chunk_Size);
            S    : constant String := B.Text.Slice (Pos, To);
            Data : Stream_Element_Array (1 .. Stream_Element_Offset (S'Length));
         begin
            for I in S'Range loop
               Data (Stream_Element_Offset (I)) :=
                 Stream_Element (Character'Pos (S (I)));
            end loop;
            SIO.Write (F, Data);
            Pos := To;
         end;
      end loop;
      SIO.Close (F);
   exception
      when others =>
         if SIO.Is_Open (F) then
            SIO.Close (F);
         end if;
         raise;
   end Write_Contents;

   procedure Save
     (B       : in out Buffer;
      Message : out Unbounded_String;
      Success : out Boolean)
   is
      Name   : constant String := To_String (B.File_Name);
      Target : constant String := File_IO.Resolve (Name);  --  Through symlinks
      Before : constant File_IO.File_Info := File_IO.Info (Target);
      Temp   : constant String :=
        Ada.Directories.Containing_Directory (Target) & "/."
        & Ada.Directories.Simple_Name (Target) & ".avoe-save";
      Backup_Failed : Boolean := False;
   begin
      if Before.Exists and then not Before.Regular then
         Message := To_Unbounded_String (Name & " is not a regular file");
         Success := False;
         return;
      end if;

      if Make_Backups and then Before.Exists and then not B.Backup_Made then
         B.Backup_Made := File_IO.Copy (Target, Target & "~");
         Backup_Failed := not B.Backup_Made;
      end if;

      --  Write a temporary file next to the target and rename it into place,
      --  so a crash or a full disk never leaves a half-written file.  If the
      --  directory is not writable, write the file directly instead.
      begin
         Write_Contents (B, Temp);
         File_IO.Sync (Temp);
         if Before.Exists then
            File_IO.Set_Mode (Temp, Before.Mode);
         end if;
         if not File_IO.Rename (Temp, Target) then
            raise Program_Error with "rename failed";
         end if;
      exception
         when others =>
            File_IO.Delete (Temp);
            Write_Contents (B, Target);
      end;

      --  Undoing past this point now makes the buffer differ from the file
      for R of B.Undo_List loop
         R.Was_Modified := True;
      end loop;
      B.Modified := False;
      B.Auto_Save_Tick := B.Change_Tick;
      Remember_Disk_State (B);
      Message := To_Unbounded_String
        ("Wrote " & Name & (if Backup_Failed then " (could not make a backup)" else ""));
      Success := True;
   exception
      when E : others =>
         Message := To_Unbounded_String
           ("Cannot write " & Name & ": " & Ada.Exceptions.Exception_Message (E));
         Success := False;
   end Save;

   procedure Write_Copy (B : Buffer; Path : String; Success : out Boolean) is
   begin
      Write_Contents (B, Path);
      File_IO.Set_Mode (Path, 8#600#);
      Success := True;
   exception
      when others =>
         Success := False;
   end Write_Copy;

   procedure Revert
     (B       : in out Buffer;
      Message : out Unbounded_String;
      Success : out Boolean)
   is
      Point     : constant Natural := B.Point;
      Read_Only : constant Boolean := B.Read_Only;
   begin
      Load (B, To_String (B.File_Name), Message, Success);
      if Success then
         B.Point := Natural'Min (Point, Length (B));
         B.Read_Only := Read_Only;
         Message := To_Unbounded_String ("Reverted " & To_String (B.File_Name));
      end if;
   end Revert;

end Buffers;
