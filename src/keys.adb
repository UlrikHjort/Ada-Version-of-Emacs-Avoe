-- ***************************************************************************
--                                Avoe - Keys
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
with Terminal;

package body Keys is

   Replacement      : constant := 16#FFFD#;
   Sequence_Timeout : constant := 50;  --  ms to wait for the rest of a sequence

   function Plain (Code : Natural) return Key is
     (Code => Code, Meta => False, Ctrl => False);

   function Next_Byte return Integer is
      B : constant Integer := Terminal.Read_Byte (Sequence_Timeout);
   begin
      return (if B < 0 then -1 else B);
   end Next_Byte;

   --  A character typed as several UTF-8 bytes; invalid bytes become U+FFFD
   function Decode_UTF8 (First : Natural) return Key is
      Need : Natural;
      Code : Natural;
      B    : Integer;
   begin
      case First is
         when 0 .. 16#7F# =>
            return Plain (First);
         when 16#C2# .. 16#DF# =>
            Need := 1;
            Code := First - 16#C0#;
         when 16#E0# .. 16#EF# =>
            Need := 2;
            Code := First - 16#E0#;
         when 16#F0# .. 16#F4# =>
            Need := 3;
            Code := First - 16#F0#;
         when others =>
            return Plain (Replacement);
      end case;

      for I in 1 .. Need loop
         B := Next_Byte;
         if B not in 16#80# .. 16#BF# then
            return Plain (Replacement);
         end if;
         Code := Code * 64 + (B - 16#80#);
      end loop;
      return Plain (Code);
   end Decode_UTF8;

   --  ESC [ params final
   function Read_CSI return Key is
      Params   : array (1 .. 4) of Natural := (others => 0);
      Count    : Positive := 1;
      B        : Integer;
      K        : Key;
      Modifier : Natural;
   begin
      loop
         B := Next_Byte;
         if B < 0 then
            return Plain (Key_None);
         end if;
         case B is
            when Character'Pos ('0') .. Character'Pos ('9') =>
               if Params (Count) < 10_000 then
                  Params (Count) :=
                    Params (Count) * 10 + (B - Character'Pos ('0'));
               end if;
            when Character'Pos (';') =>
               if Count < Params'Last then
                  Count := Count + 1;
               end if;
            when 16#40# .. 16#7E# =>
               exit;
            when others =>
               null;
         end case;
      end loop;

      case B is
         when Character'Pos ('A') => K := Plain (Key_Up);
         when Character'Pos ('B') => K := Plain (Key_Down);
         when Character'Pos ('C') => K := Plain (Key_Right);
         when Character'Pos ('D') => K := Plain (Key_Left);
         when Character'Pos ('H') => K := Plain (Key_Home);
         when Character'Pos ('F') => K := Plain (Key_End);
         when Character'Pos ('~') =>
            case Params (1) is
               when 1 | 7  => K := Plain (Key_Home);
               when 4 | 8  => K := Plain (Key_End);
               when 2      => K := Plain (Key_Insert);
               when 3      => K := Plain (Key_Delete);
               when 5      => K := Plain (Key_Page_Up);
               when 6      => K := Plain (Key_Page_Down);
               when others => K := Plain (Key_None);
            end case;
         when others =>
            K := Plain (Key_None);
      end case;

      --  xterm modifiers: the second parameter is 1 + Shift 1 + Alt 2 +
      --  Ctrl 4, so ESC [ 1 ; 5 C is C-<right>
      if Count >= 2 and then Params (2) >= 2 then
         Modifier := Params (2) - 1;
         K.Meta := (Modifier / 2) mod 2 = 1;
         K.Ctrl := (Modifier / 4) mod 2 = 1;
      end if;
      return K;
   end Read_CSI;

   --  ESC O final
   function Read_SS3 return Key is
      B : constant Integer := Next_Byte;
   begin
      case B is
         when Character'Pos ('A') => return Plain (Key_Up);
         when Character'Pos ('B') => return Plain (Key_Down);
         when Character'Pos ('C') => return Plain (Key_Right);
         when Character'Pos ('D') => return Plain (Key_Left);
         when Character'Pos ('H') => return Plain (Key_Home);
         when Character'Pos ('F') => return Plain (Key_End);
         when others              => return Plain (Key_None);
      end case;
   end Read_SS3;

   Pending     : Key;
   Has_Pending : Boolean := False;

   procedure Unread (K : Key) is
   begin
      Pending := K;
      Has_Pending := True;
   end Unread;

   function Read_Terminal_Key return Key is
      B : Integer;
   begin
      loop
         B := Terminal.Read_Byte (-1);
         exit when B >= 0;
         if B = -2 and then Terminal.Take_Resized then
            return Plain (Key_Resize);
         end if;
      end loop;

      if B /= Esc then
         return Decode_UTF8 (B);
      end if;

      --  A byte right after ESC is an escape sequence or a Meta key (how
      --  terminals send Alt); ESC alone for a moment is the ESC key itself
      B := Next_Byte;
      if B < 0 then
         return Plain (Esc);
      elsif B = Character'Pos ('[') then
         return Read_CSI;
      elsif B = Character'Pos ('O') then
         return Read_SS3;
      else
         declare
            K : Key := Decode_UTF8 (B);
         begin
            K.Meta := True;
            return K;
         end;
      end if;
   end Read_Terminal_Key;

   -------------------------------------------------------------------------
   --  Keyboard macros
   -------------------------------------------------------------------------

   package Key_Vectors is new Ada.Containers.Vectors (Positive, Key);

   Max_Macro_Keys : constant := 100_000;

   Defining      : Key_Vectors.Vector;  --  The macro being recorded
   Is_Recording  : Boolean := False;
   Last_Macro    : Key_Vectors.Vector;
   Queue         : Key_Vectors.Vector;  --  Keys of the macro being played
   Queue_Pos     : Positive := 1;

   procedure Start_Recording is
   begin
      Defining.Clear;
      Is_Recording := True;
   end Start_Recording;

   procedure Stop_Recording (Keep : Natural) is
   begin
      Is_Recording := False;
      Last_Macro.Clear;
      for I in 1 .. Natural'Min (Keep, Natural (Defining.Length)) loop
         Last_Macro.Append (Defining (I));
      end loop;
      Defining.Clear;
   end Stop_Recording;

   function Recording return Boolean is (Is_Recording);
   function Recorded_Count return Natural is (Natural (Defining.Length));
   function Have_Macro return Boolean is (not Last_Macro.Is_Empty);

   procedure Play_Macro is
   begin
      Queue := Last_Macro;
      Queue_Pos := 1;
   end Play_Macro;

   function Playing return Boolean is (Queue_Pos <= Queue.Last_Index);

   procedure Cancel_Playback is
   begin
      Queue.Clear;
      Queue_Pos := 1;
   end Cancel_Playback;

   function Key_Pending return Boolean is (Has_Pending or else Playing);

   function Read_Key return Key is
      K : Key;
   begin
      if Has_Pending then
         Has_Pending := False;
         return Pending;
      elsif Playing then
         K := Queue (Queue_Pos);
         Queue_Pos := Queue_Pos + 1;
         return K;
      end if;
      K := Read_Terminal_Key;
      if Is_Recording and then K.Code /= Key_None and then K.Code /= Key_Resize
        and then Natural (Defining.Length) < Max_Macro_Keys
      then
         Defining.Append (K);
      end if;
      return K;
   end Read_Key;

   function Is_Self_Inserting (K : Key) return Boolean is
     (not K.Meta and then not K.Ctrl
      and then K.Code >= 32 and then K.Code /= Del
      and then K.Code < Key_None);

   function Encode_UTF8 (Code : Natural) return String is
      function B (N : Natural) return Character is (Character'Val (N));
   begin
      if Code < 16#80# then
         return (1 => B (Code));
      elsif Code < 16#800# then
         return (B (16#C0# + Code / 64), B (16#80# + Code mod 64));
      elsif Code < 16#1_0000# then
         return (B (16#E0# + Code / 4096),
                 B (16#80# + (Code / 64) mod 64),
                 B (16#80# + Code mod 64));
      elsif Code < Key_None then
         return (B (16#F0# + Code / 262_144),
                 B (16#80# + (Code / 4096) mod 64),
                 B (16#80# + (Code / 64) mod 64),
                 B (16#80# + Code mod 64));
      else
         return "";
      end if;
   end Encode_UTF8;

   function Base_Name (Code : Natural) return String is
   begin
      case Code is
         when Ctl_Space            => return "C-SPC";
         when Tab                  => return "TAB";
         when Ret                  => return "RET";
         when Esc                  => return "ESC";
         when 32                   => return "SPC";
         when Del                  => return "DEL";
         when 1 .. 8 | 10 .. 12 | 14 .. 26 =>
            return "C-" & Character'Val (Code + 96);
         when 28 .. 31 =>
            return "C-" & Character'Val (Code + 64);
         when Key_Up        => return "<up>";
         when Key_Down      => return "<down>";
         when Key_Left      => return "<left>";
         when Key_Right     => return "<right>";
         when Key_Home      => return "<home>";
         when Key_End       => return "<end>";
         when Key_Page_Up   => return "<prior>";
         when Key_Page_Down => return "<next>";
         when Key_Insert    => return "<insert>";
         when Key_Delete    => return "<delete>";
         when Key_None      => return "<unknown>";
         when Key_Resize    => return "<resize>";
         when others        => return Encode_UTF8 (Code);
      end case;
   end Base_Name;

   function Describe (K : Key) return String is
     ((if K.Meta then "M-" else "") & (if K.Ctrl then "C-" else "")
      & Base_Name (K.Code));

end Keys;
