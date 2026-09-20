-- ***************************************************************************
--                             Avoe - Minibuffer
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
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Text_IO;
with Display;
with Kill_Ring;
with Utils; use Utils;

package body Minibuffer is

   Current : Unbounded_String;

   procedure Message (Text : String) is
   begin
      Current := To_Unbounded_String (Text);
      if Batch_Mode and then Text /= "" then
         Ada.Text_IO.Put_Line (Text);
      end if;
   end Message;

   function Current_Message return String is (To_String (Current));

   procedure Clear_Message is
   begin
      Current := Null_Unbounded_String;
   end Clear_Message;

   procedure Redisplay is
   begin
      Display.Render (To_String (Current));
   end Redisplay;

   function Read_Key_Echo (Echo : String; Cursor_At_End : Boolean := False) return Key is
      K : Key;
   begin
      if Batch_Mode then
         raise Not_Interactive;
      end if;
      loop
         Display.Render (Echo, (if Cursor_At_End then Cell_Count (Echo) else -1));
         K := Read_Key;
         if K.Code = Key_Resize then
            Display.Update_Size;
         elsif K.Code /= Key_None then
            return K;
         end if;
      end loop;
   end Read_Key_Echo;

   function Common_Prefix (V : String_Vectors.Vector) return String is
      First : constant String := V.First_Element;
      Last  : Natural := First'Length;
   begin
      for S of V loop
         declare
            N : Natural := 0;
         begin
            while N < Last and then N < S'Length
              and then S (S'First + N) = First (First'First + N)
            loop
               N := N + 1;
            end loop;
            Last := N;
         end;
      end loop;
      return First (First'First .. First'First + Last - 1);
   end Common_Prefix;

   function Short_Name (S : String) return String is
      Stop  : constant Natural := (if S'Length > 1 and then S (S'Last) = '/' then S'Last - 1 else S'Last);
      Slash : constant Natural :=
        Ada.Strings.Fixed.Index (S (S'First .. Stop), "/", Ada.Strings.Backward);
   begin
      return (if Slash = 0 then S else S (Slash + 1 .. S'Last));
   end Short_Name;

   procedure Do_Complete
     (Complete : Completer;
      Input    : in out Unbounded_String;
      Hint     : out Unbounded_String)
   is
      Candidates : constant String_Vectors.Vector := Complete (To_String (Input));
   begin
      Hint := Null_Unbounded_String;
      if Candidates.Is_Empty then
         Hint := To_Unbounded_String ("  [No match]");
      elsif Natural (Candidates.Length) = 1 then
         if Candidates.First_Element = To_String (Input) then
            Hint := To_Unbounded_String ("  [Sole completion]");
         end if;
         Input := To_Unbounded_String (Candidates.First_Element);
      else
         declare
            Prefix : constant String := Common_Prefix (Candidates);
         begin
            if Prefix'Length > Length (Input) then
               Input := To_Unbounded_String (Prefix);
            else
               Hint := To_Unbounded_String ("  {");
               for I in 1 .. Candidates.Last_Index loop
                  if I > 1 then
                     Append (Hint, " | ");
                  end if;
                  Append (Hint, Short_Name (Candidates (I)));
                  if Length (Hint) > 1000 then
                     Append (Hint, " ...");
                     exit;
                  end if;
               end loop;
               Append (Hint, "}");
            end if;
         end;
      end if;
   end Do_Complete;

   -------------------------------------------------------------------------
   --  History
   -------------------------------------------------------------------------

   Max_History : constant := 100;

   package History_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String_Vectors.Vector, Ada.Strings.Hash, "=", String_Vectors."=");

   Histories : History_Maps.Map;

   function History_Of (Key : String) return String_Vectors.Vector is
     (if Histories.Contains (Key) then Histories.Element (Key)
      else String_Vectors.Empty_Vector);

   procedure Remember (Key, Text : String) is
      H : String_Vectors.Vector := History_Of (Key);
   begin
      if Text = "" or else (not H.Is_Empty and then H.Last_Element = Text) then
         return;
      end if;
      H.Append (Text);
      if Natural (H.Length) > Max_History then
         H.Delete_First;
      end if;
      Histories.Include (Key, H);
   end Remember;

   -------------------------------------------------------------------------
   --  Line input
   -------------------------------------------------------------------------

   function Is_Word_Byte (C : Character) return Boolean is
     (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' or else Character'Pos (C) >= 128);

   procedure Read_String
     (Prompt   : String;
      Initial  : String;
      Result   : out Unbounded_String;
      Ok       : out Boolean;
      Complete : Completer := null;
      History  : String := "")
   is
      Key_Name : constant String := (if History = "" then Prompt else History);
      Past     : constant String_Vectors.Vector := History_Of (Key_Name);
      Browsing : Natural := 0;              --  0: editing; N: N-th newest entry
      Typed    : Unbounded_String;          --  Input saved while browsing
      Cursor   : Natural := Initial'Length; --  Bytes before the cursor
      K        : Key;
      Hint     : Unbounded_String;

      function Len return Natural is (Length (Result));
      function Byte (Offset : Natural) return Character is (Element (Result, Offset + 1));

      function Previous (From : Natural) return Natural is
         C : Natural := From;
      begin
         if C > 0 then
            C := C - 1;
            while C > 0 and then Is_Continuation (Byte (C)) loop
               C := C - 1;
            end loop;
         end if;
         return C;
      end Previous;

      function Next (From : Natural) return Natural is
         C : Natural := From;
      begin
         if C < Len then
            C := C + 1;
            while C < Len and then Is_Continuation (Byte (C)) loop
               C := C + 1;
            end loop;
         end if;
         return C;
      end Next;

      procedure Insert_Text (Text : String) is
      begin
         Insert (Result, Cursor + 1, Text);
         Cursor := Cursor + Text'Length;
      end Insert_Text;

      procedure Remove (From, To : Natural) is
      begin
         if From < To then
            Delete (Result, From + 1, To);
            if Cursor > From then
               Cursor := Natural'Max (From, Cursor - (To - From));
            end if;
         end if;
      end Remove;

      procedure Show_Entry (Text : String) is
      begin
         Result := To_Unbounded_String (Text);
         Cursor := Text'Length;
      end Show_Entry;

   begin
      if Batch_Mode then
         raise Not_Interactive;
      end if;
      Result := To_Unbounded_String (Initial);
      loop
         declare
            Text : constant String := To_String (Result);
         begin
            --  The cursor column counts characters, Cursor counts bytes
            Display.Render (Prompt & Text & To_String (Hint),
                            Cell_Count (Prompt & Text (Text'First .. Text'First + Cursor - 1)));
         end;
         K := Read_Key;
         Hint := Null_Unbounded_String;

         if K.Code = Key_Resize then
            Display.Update_Size;

         elsif K.Meta then
            case K.Code is
               when Character'Pos ('p') =>
                  if Browsing < Natural (Past.Length) then
                     --  Keep what was typed, for M-n to come back to
                     if Browsing = 0 then
                        Typed := Result;
                     end if;
                     Browsing := Browsing + 1;
                     Show_Entry (Past (Past.Last_Index - Browsing + 1));
                  end if;
               when Character'Pos ('n') =>
                  if Browsing > 0 then
                     Browsing := Browsing - 1;
                     Show_Entry (if Browsing = 0 then To_String (Typed)
                                 else Past (Past.Last_Index - Browsing + 1));
                  end if;
               when Character'Pos ('b') =>
                  while Cursor > 0 and then not Is_Word_Byte (Byte (Cursor - 1)) loop
                     Cursor := Cursor - 1;
                  end loop;
                  while Cursor > 0 and then Is_Word_Byte (Byte (Cursor - 1)) loop
                     Cursor := Cursor - 1;
                  end loop;
               when Character'Pos ('f') =>
                  while Cursor < Len and then not Is_Word_Byte (Byte (Cursor)) loop
                     Cursor := Cursor + 1;
                  end loop;
                  while Cursor < Len and then Is_Word_Byte (Byte (Cursor)) loop
                     Cursor := Cursor + 1;
                  end loop;
               when Del | Ctl_H =>
                  declare
                     Start : Natural := Cursor;
                  begin
                     while Start > 0 and then not Is_Word_Byte (Byte (Start - 1)) loop
                        Start := Start - 1;
                     end loop;
                     while Start > 0 and then Is_Word_Byte (Byte (Start - 1)) loop
                        Start := Start - 1;
                     end loop;
                     Remove (Start, Cursor);
                  end;
               when others =>
                  null;
            end case;

         --  Up and Down browse the history, like M-p and M-n
         elsif K.Code = Key_Up then
            Unread ((Code => Character'Pos ('p'), Meta => True, Ctrl => False));
         elsif K.Code = Key_Down then
            Unread ((Code => Character'Pos ('n'), Meta => True, Ctrl => False));

         --  Other special keys (C-<right> and the like) do nothing here
         elsif K.Ctrl or else K.Code = Key_None then
            null;
         elsif K.Code = Ret then
            Remember (Key_Name, To_String (Result));
            Ok := True;
            return;
         elsif K.Code = Ctl_G then
            Message ("Quit");
            Ok := False;
            return;
         elsif K.Code = Ctl_A or else K.Code = Key_Home then
            Cursor := 0;
         elsif K.Code = Ctl_E or else K.Code = Key_End then
            Cursor := Len;
         elsif K.Code = Ctl_B or else K.Code = Key_Left then
            Cursor := Previous (Cursor);
         elsif K.Code = Ctl_F or else K.Code = Key_Right then
            Cursor := Next (Cursor);
         elsif K.Code = Del or else K.Code = Ctl_H then
            Remove (Previous (Cursor), Cursor);
         elsif K.Code = Ctl_D or else K.Code = Key_Delete then
            Remove (Cursor, Next (Cursor));
         elsif K.Code = Ctl_K then
            if Cursor < Len then
               Kill_Ring.Push (To_Unbounded_String (Slice (Result, Cursor + 1, Len)));
            end if;
            Remove (Cursor, Len);
         elsif K.Code = Ctl_U then
            Show_Entry ("");
         --  The input is one line, so only the first line of the kill is yanked
         elsif K.Code = Ctl_Y then
            declare
               Text : constant String := To_String (Kill_Ring.Current);
               NL   : constant Natural :=
                 Ada.Strings.Fixed.Index (Text, (1 => Ada.Characters.Latin_1.LF));
            begin
               Insert_Text (if NL = 0 then Text else Text (Text'First .. NL - 1));
            end;
         elsif K.Code = Tab then
            if Complete /= null then
               Do_Complete (Complete, Result, Hint);
               Cursor := Len;
            end if;
         elsif Is_Self_Inserting (K) then
            Insert_Text (Encode_UTF8 (K.Code));
         end if;
      end loop;
   end Read_String;

   function Ask (Question : String) return Answer is
      K : Key;
   begin
      loop
         K := Read_Key_Echo (Question & " (y or n) ", Cursor_At_End => True);
         if not K.Meta then
            case K.Code is
               when Character'Pos ('y') | Character'Pos ('Y') =>
                  return Yes;
               when Character'Pos ('n') | Character'Pos ('N') =>
                  return No;
               when Ctl_G =>
                  Message ("Quit");
                  return Cancel;
               when others =>
                  null;
            end case;
         end if;
      end loop;
   end Ask;

   function Ask_Yes_Or_No (Question : String) return Answer is
      Prompt : Unbounded_String := To_Unbounded_String (Question & " (yes or no) ");
      Input  : Unbounded_String;
      Ok     : Boolean;
   begin
      loop
         Read_String (To_String (Prompt), "", Input, Ok, History => "yes or no");
         if not Ok then
            Message ("Quit");
            return Cancel;
         end if;
         declare
            Reply : String := To_String (Input);
         begin
            for C of Reply loop
               if C in 'A' .. 'Z' then
                  C := Character'Val (Character'Pos (C) + 32);
               end if;
            end loop;
            if Reply = "yes" then
               return Yes;
            elsif Reply = "no" then
               return No;
            end if;
         end;
         --  Short enough for an 80-column echo area
         Prompt := To_Unbounded_String (Question & " (please type yes or no) ");
      end loop;
   end Ask_Yes_Or_No;

end Minibuffer;
