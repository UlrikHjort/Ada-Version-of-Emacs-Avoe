-- ***************************************************************************
--                                Avoe - Utils
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

package body Utils is

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Img;

   function Hex (N : Natural) return String is
      Digits_Str : constant String := "0123456789abcdef";
   begin
      if N < 16 then
         return (1 => Digits_Str (N + 1));
      end if;
      return Hex (N / 16) & Digits_Str (N mod 16 + 1);
   end Hex;

   --  UTF-8 text is measured in characters: continuation bytes don't count.
   --  (Wide characters such as CJK are counted as one cell too.)
   function Cell_Count (S : String) return Natural is
      N : Natural := 0;
   begin
      for C of S loop
         if not Is_Continuation (C) then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Cell_Count;

   function Head_Cells (S : String; N : Natural) return String is
      Count : Natural := 0;
   begin
      for I in S'Range loop
         if not Is_Continuation (S (I)) then
            if Count = N then
               return S (S'First .. I - 1);
            end if;
            Count := Count + 1;
         end if;
      end loop;
      return S;
   end Head_Cells;

   function Tail_Cells (S : String; N : Natural) return String is
      Count : Natural := 0;
   begin
      if N = 0 then
         return "";
      end if;
      for I in reverse S'Range loop
         if not Is_Continuation (S (I)) then
            Count := Count + 1;
            if Count = N then
               return S (I .. S'Last);
            end if;
         end if;
      end loop;
      return S;
   end Tail_Cells;

   function Pad (S : String; Width : Natural) return String is
      N : constant Natural := Cell_Count (S);
   begin
      return (if N >= Width then S else S & (1 .. Width - N => ' '));
   end Pad;

   --  Remove a whole UTF-8 character, not just its last byte
   function Drop_Last_Char (S : String) return String is
      I : Integer := S'Last;
   begin
      if S'Length = 0 then
         return "";
      end if;
      while I > S'First and then Is_Continuation (S (I)) loop
         I := I - 1;
      end loop;
      return S (S'First .. I - 1);
   end Drop_Last_Char;

   --  The code point of the first UTF-8 character; U+FFFD (the replacement
   --  character) for an invalid or incomplete sequence
   function Decode_First (S : String) return Natural is
      Replacement : constant := 16#FFFD#;
      First       : Natural;
      Need        : Natural;
      Code        : Natural;
   begin
      if S'Length = 0 then
         return Replacement;
      end if;
      First := Character'Pos (S (S'First));
      case First is
         when 0 .. 16#7F#      => return First;
         when 16#C2# .. 16#DF# => Need := 1; Code := First - 16#C0#;
         when 16#E0# .. 16#EF# => Need := 2; Code := First - 16#E0#;
         when 16#F0# .. 16#F4# => Need := 3; Code := First - 16#F0#;
         when others           => return Replacement;
      end case;
      if S'Length <= Need then
         return Replacement;
      end if;
      for I in 1 .. Need loop
         if not Is_Continuation (S (S'First + I)) then
            return Replacement;
         end if;
         Code := Code * 64 + (Character'Pos (S (S'First + I)) - 16#80#);
      end loop;
      return Code;
   end Decode_First;

   function To_Lower (C : Character) return Character is
     (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C);

   function To_Upper (C : Character) return Character is
     (if C in 'a' .. 'z' then Character'Val (Character'Pos (C) - 32) else C);

   function Starts_With (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

end Utils;
