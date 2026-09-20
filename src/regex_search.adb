-- ***************************************************************************
--                            Avoe - Regex_Search
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

with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with GNAT.Regpat;           use GNAT.Regpat;

package body Regex_Search is

   type Matcher_Access is access Pattern_Matcher;
   procedure Free is new Ada.Unchecked_Deallocation (Pattern_Matcher, Matcher_Access);

   --  The most recently compiled pattern is kept, since searches repeat
   Cached         : Matcher_Access;
   Cached_Pattern : Unbounded_String;
   Cached_Fold    : Boolean := False;

   function Matcher (Pattern : String; Fold : Boolean) return Matcher_Access is
   begin
      if Cached = null or else To_String (Cached_Pattern) /= Pattern or else Cached_Fold /= Fold then
         declare
            New_Matcher : constant Matcher_Access :=
              new Pattern_Matcher'(Compile (Pattern, (if Fold then Case_Insensitive else No_Flags)));
         begin
            Free (Cached);
            Cached := New_Matcher;
            Cached_Pattern := To_Unbounded_String (Pattern);
            Cached_Fold := Fold;
         end;
      end if;
      return Cached;
   exception
      when E : Expression_Error =>
         raise Invalid_Pattern with Ada.Exceptions.Exception_Message (E);
   end Matcher;

   procedure Check (Pattern : String) is
      M : constant Matcher_Access := Matcher (Pattern, False);
      pragma Unreferenced (M);
   begin
      null;
   end Check;

   function Folds (Pattern : String) return Boolean is
      I : Integer := Pattern'First;
   begin
      while I <= Pattern'Last loop
         if Pattern (I) = '\' then
            I := I + 2;   --  \S, \W, \D are not upper-case letters
         elsif Pattern (I) in 'A' .. 'Z' then
            return False;
         else
            I := I + 1;
         end if;
      end loop;
      return True;
   end Folds;

   --  Match in the line Text (which starts at buffer position Line_Pos),
   --  beginning the search at byte offset Offset.
   function Match_Line
     (M        : Matcher_Access;
      Text     : String;
      Line_Pos : Natural;
      Offset   : Natural) return Match_Result
   is
      Matches : Match_Array (0 .. Max_Groups);
      Result  : Match_Result;
   begin
      if Text'Length = 0 then
         if Offset > 0 then
            return Result;
         end if;
         Match (M.all, Text, Matches);
      elsif Offset >= Text'Length then
         return Result;
      else
         --  Data_First instead of a slice, so that ^ still means the start
         --  of the line
         Match (M.all, Text, Matches, Data_First => Text'First + Offset);
      end if;

      if Matches (0) = No_Match then
         return Result;
      end if;
      Result.Found := True;
      for G in Matches'Range loop
         if Matches (G) /= No_Match then
            Result.Groups (G) :=
              (Matched => True,
               Start   => Line_Pos + (Matches (G).First - Text'First),
               Stop    => Line_Pos + (Matches (G).Last - Text'First + 1));
         end if;
      end loop;
      return Result;
   end Match_Line;

   --  Searching goes a line at a time: ^ and $ are the line's start and end,
   --  and a match never spans lines
   function Search_Forward
     (B : Buffer; Pattern : String; From : Natural; Fold : Boolean) return Match_Result
   is
      M   : constant Matcher_Access := Matcher (Pattern, Fold);
      Len : constant Natural := Length (B);
      LS  : Natural := Line_Start (B, Natural'Min (From, Len));
      LE  : Natural;
   begin
      loop
         LE := Line_End (B, LS);
         declare
            R : constant Match_Result :=
              Match_Line (M, Slice (B, LS, LE), LS, (if From > LS then From - LS else 0));
         begin
            if R.Found then
               return R;
            end if;
         end;
         exit when LE >= Len;
         LS := LE + 1;
      end loop;
      return (Found => False, others => <>);
   end Search_Forward;

   function Search_Backward
     (B : Buffer; Pattern : String; From : Integer; Fold : Boolean) return Match_Result
   is
      M     : constant Matcher_Access := Matcher (Pattern, Fold);
      Len   : constant Natural := Length (B);
      LS    : Natural;
      Limit : Integer;  --  Latest allowed start, as an offset in the line
   begin
      if From < 0 then
         return (Found => False, others => <>);
      end if;
      LS := Line_Start (B, Natural'Min (From, Len));
      Limit := Natural'Min (From, Len) - LS;

      loop
         declare
            Text   : constant String := Slice (B, LS, Line_End (B, LS));
            Best   : Match_Result;
            Offset : Natural := 0;
         begin
            --  The matcher only searches forward: keep the last match in the
            --  line that starts no later than Limit
            loop
               declare
                  R : constant Match_Result := Match_Line (M, Text, LS, Offset);
               begin
                  exit when not R.Found or else R.Groups (0).Start - LS > Limit;
                  Best := R;
                  Offset := R.Groups (0).Start - LS + 1;
                  exit when Offset > Text'Length;
               end;
            end loop;
            if Best.Found then
               return Best;
            end if;
         end;
         exit when LS = 0;
         LS := Line_Start (B, LS - 1);
         Limit := Line_End (B, LS) - LS;
      end loop;
      return (Found => False, others => <>);
   end Search_Backward;

   --  The replacement text: \1 .. \9 insert groups, \& the whole match, and
   --  a backslash before any other character inserts that character
   function Expand (B : Buffer; M : Match_Result; Replacement : String) return String is
      Result : Unbounded_String;
      I      : Integer := Replacement'First;

      procedure Add_Group (N : Natural) is
      begin
         if M.Groups (N).Matched then
            Append (Result, Slice (B, M.Groups (N).Start, M.Groups (N).Stop));
         end if;
      end Add_Group;
   begin
      while I <= Replacement'Last loop
         if Replacement (I) = '\' and then I < Replacement'Last then
            declare
               C : constant Character := Replacement (I + 1);
            begin
               if C in '0' .. '9' then
                  Add_Group (Character'Pos (C) - Character'Pos ('0'));
               elsif C = '&' then
                  Add_Group (0);
               else
                  Append (Result, C);
               end if;
            end;
            I := I + 2;
         else
            Append (Result, Replacement (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Expand;

end Regex_Search;
