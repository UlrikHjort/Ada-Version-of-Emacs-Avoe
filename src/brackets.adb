-- ***************************************************************************
--                              Avoe - Brackets
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

package body Brackets is

   function Partner (C : Character) return Character is
     (case C is
         when '(' => ')', when ')' => '(',
         when '[' => ']', when ']' => '[',
         when '{' => '}', when '}' => '{',
         when others => C);

   --  Scan forward from an opening bracket (backward from a closing one),
   --  counting the nesting of all bracket kinds.  A bracket closed by the
   --  wrong kind gives -1, and so does anything beyond Max_Distance, which
   --  keeps this cheap in big files.
   function Matching (B : Buffer; Pos : Natural) return Integer is
      Len   : constant Natural := Length (B);
      C     : Character;
      Depth : Natural := 0;
   begin
      if Pos >= Len then
         return -1;
      end if;
      C := Char_At (B, Pos);

      if Is_Open (C) then
         for P in Pos .. Natural'Min (Len - 1, Pos + Max_Distance) loop
            if Is_Open (Char_At (B, P)) then
               Depth := Depth + 1;
            elsif Is_Close (Char_At (B, P)) then
               Depth := Depth - 1;
               if Depth = 0 then
                  return (if Char_At (B, P) = Partner (C) then P else -1);
               end if;
            end if;
         end loop;

      elsif Is_Close (C) then
         for P in reverse Integer'Max (0, Pos - Max_Distance) .. Pos loop
            if Is_Close (Char_At (B, P)) then
               Depth := Depth + 1;
            elsif Is_Open (Char_At (B, P)) then
               Depth := Depth - 1;
               if Depth = 0 then
                  return (if Char_At (B, P) = Partner (C) then P else -1);
               end if;
            end if;
         end loop;
      end if;
      return -1;
   end Matching;

   --  As in Emacs: an opening bracket after point, or else a closing bracket
   --  just before it
   procedure Pair_At (B : Buffer; Point : Natural; Open_Pos, Close_Pos : out Integer) is
   begin
      Open_Pos := -1;
      Close_Pos := -1;
      if Point < Length (B) and then Is_Open (Char_At (B, Point)) then
         Close_Pos := Matching (B, Point);
         if Close_Pos >= 0 then
            Open_Pos := Point;
         end if;
      elsif Point > 0 and then Point <= Length (B) and then Is_Close (Char_At (B, Point - 1)) then
         Open_Pos := Matching (B, Point - 1);
         if Open_Pos >= 0 then
            Close_Pos := Point - 1;
         end if;
      end if;
   end Pair_At;

end Brackets;
