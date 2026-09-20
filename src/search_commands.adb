-- ***************************************************************************
--                           Avoe - Search_Commands
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Buffers;      use Buffers;
with Commands;     use Commands;
with Display;
with Keys;         use Keys;
with Minibuffer;   use Minibuffer;
with Regex_Search;
with Utils;        use Utils;
with Windows;

package body Search_Commands is

   Last_Search : Unbounded_String;
   Last_Regexp : Unbounded_String;

   --  As in Emacs, a search ignores case unless the pattern has upper case
   function Folds (Pattern : String) return Boolean is
   begin
      for C of Pattern loop
         if C in 'A' .. 'Z' then
            return False;
         end if;
      end loop;
      return True;
   end Folds;

   -------------------------------------------------------------------------
   --  Incremental search
   -------------------------------------------------------------------------

   type Search_State is record
      Pattern     : Unbounded_String;
      Point       : Natural := 0;
      Match_Start : Natural := 0;
      Match_End   : Natural := 0;
      Failing     : Boolean := False;
      Invalid     : Boolean := False;   --  Regexp does not compile (yet)
      Wrapped     : Boolean := False;
      Forward     : Boolean := True;
   end record;

   --  Every key pushes the search state, so DEL can go back one step and
   --  C-g back to the last search that did not fail
   package State_Vectors is new Ada.Containers.Vectors (Positive, Search_State);

   procedure Isearch (Forward : Boolean; Regexp : Boolean) is
      B     : Buffer renames Windows.Current_Buffer.all;
      Start : constant Natural := B.Point;
      S     : Search_State :=
        (Pattern     => Null_Unbounded_String,
         Point       => Start,
         Match_Start => Start,
         Match_End   => Start,
         Failing     => False,
         Invalid     => False,
         Wrapped     => False,
         Forward     => Forward);
      Stack : State_Vectors.Vector;
      K     : Key;

      procedure Find (From : Integer) is
         P : constant String := To_String (S.Pattern);
      begin
         S.Invalid := False;
         if P = "" then
            S.Failing := False;
            return;
         end if;

         if Regexp then
            declare
               R : constant Regex_Search.Match_Result :=
                 (if S.Forward
                  then Regex_Search.Search_Forward
                         (B, P, Natural (Integer'Max (0, From)), Regex_Search.Folds (P))
                  else Regex_Search.Search_Backward (B, P, From, Regex_Search.Folds (P)));
            begin
               S.Failing := not R.Found;
               if R.Found then
                  S.Match_Start := R.Groups (0).Start;
                  S.Match_End := R.Groups (0).Stop;
               end if;
            end;
         else
            declare
               R : constant Integer :=
                 (if S.Forward then Search_Forward (B, P, From, Folds (P))
                  else Search_Backward (B, P, From, Folds (P)));
            begin
               S.Failing := R < 0;
               if R >= 0 then
                  S.Match_Start := R;
                  S.Match_End := R + P'Length;
               end if;
            end;
         end if;

         if not S.Failing then
            S.Point := (if S.Forward then S.Match_End else S.Match_Start);
         end if;
      exception
         when Regex_Search.Invalid_Pattern =>
            S.Failing := True;
            S.Invalid := True;
      end Find;

      --  C-s / C-r.  With nothing typed yet, search for the previous pattern.
      --  Repeating a failed search wraps around the buffer.
      procedure Repeat (Dir_Forward : Boolean) is
      begin
         Stack.Append (S);
         if Length (S.Pattern) = 0 then
            S.Pattern := (if Regexp then Last_Regexp else Last_Search);
            S.Forward := Dir_Forward;
            Find (S.Point);
         elsif Dir_Forward then
            if S.Failing and then S.Forward and then not S.Invalid then
               S.Wrapped := True;
               Find (0);
            else
               S.Forward := True;
               --  Step over an empty match so the search makes progress
               Find (if S.Match_End = S.Match_Start then S.Point + 1 else S.Point);
            end if;
         else
            if S.Failing and then not S.Forward and then not S.Invalid then
               S.Wrapped := True;
               Find (Length (B));
            else
               S.Forward := False;
               Find (S.Match_Start - 1);
            end if;
         end if;
      end Repeat;

      function Prompt return String is
        ((if S.Invalid then "Invalid " elsif S.Failing then "Failing " else "")
         & (if S.Wrapped then "Wrapped " else "")
         & (if Regexp then "Regexp I-search" else "I-search")
         & (if S.Forward then "" else " backward") & ": "
         & To_String (S.Pattern));

   begin
      loop
         B.Point := S.Point;
         if not S.Failing and then Length (S.Pattern) > 0 then
            Display.Set_Highlight (S.Match_Start, S.Match_End);
         else
            Display.Clear_Highlight;
         end if;

         K := Read_Key_Echo (Prompt, Cursor_At_End => True);

         --  Any other command key ends the search and then runs as usual
         if K.Meta or else K.Ctrl then
            Unread (K);
            exit;
         end if;

         case K.Code is
            when Ctl_S =>
               Repeat (True);
            when Ctl_R =>
               Repeat (False);
            when Del | Ctl_H =>
               if not Stack.Is_Empty then
                  S := Stack.Last_Element;
                  Stack.Delete_Last;
               end if;
            when Ctl_G =>
               if S.Failing and then not Stack.Is_Empty then
                  while S.Failing and then not Stack.Is_Empty loop
                     S := Stack.Last_Element;
                     Stack.Delete_Last;
                  end loop;
               else
                  B.Point := Start;
                  Display.Clear_Highlight;
                  Message ("Quit");
                  return;
               end if;
            when Ret =>
               exit;
            when others =>
               if Is_Self_Inserting (K) or else K.Code = Tab then
                  Stack.Append (S);
                  Append (S.Pattern, Encode_UTF8 (K.Code));
                  --  The longer pattern may still match where the last match starts
                  if S.Forward then
                     Find (S.Match_Start);
                  else
                     Find (Integer'Min (S.Match_Start, Length (B)));
                  end if;
               else
                  Unread (K);
                  exit;
               end if;
         end case;
      end loop;

      Display.Clear_Highlight;
      if Length (S.Pattern) > 0 then
         if Regexp then
            Last_Regexp := S.Pattern;
         else
            Last_Search := S.Pattern;
         end if;
      end if;
      if B.Point /= Start then
         B.Mark := Start;
         B.Mark_Set := True;
         Message ("Mark saved where search started");
      end if;
   end Isearch;

   procedure Isearch_Forward is
   begin
      Isearch (Forward => True, Regexp => False);
   end Isearch_Forward;

   procedure Isearch_Backward is
   begin
      Isearch (Forward => False, Regexp => False);
   end Isearch_Backward;

   procedure Isearch_Forward_Regexp is
   begin
      Isearch (Forward => True, Regexp => True);
   end Isearch_Forward_Regexp;

   procedure Isearch_Backward_Regexp is
   begin
      Isearch (Forward => False, Regexp => True);
   end Isearch_Backward_Regexp;

   -------------------------------------------------------------------------
   --  Replace
   -------------------------------------------------------------------------

   procedure Replace (Regexp : Boolean; Query : Boolean) is
      B        : Buffer renames Windows.Current_Buffer.all;
      What     : constant String :=
        (if Query then "Query replace" else "Replace") & (if Regexp then " regexp" else "");
      From_U   : Unbounded_String;
      To_U     : Unbounded_String;
      Ok       : Boolean;
      All_Rest : Boolean := not Query;
      Count    : Natural := 0;
      P        : Natural;
      MS, ME   : Natural := 0;   --  Current match [MS, ME)
      Found    : Regex_Search.Match_Result;
      K        : Key;
   begin
      Read_String (What & ": ", "", From_U, Ok,
                   History => (if Regexp then "replace-regexp-from" else "replace-from"));
      if not Ok or else Length (From_U) = 0 then
         return;
      end if;
      if Regexp then
         begin
            Regex_Search.Check (To_String (From_U));
         exception
            when Regex_Search.Invalid_Pattern =>
               Message ("Invalid regexp: " & To_String (From_U));
               return;
         end;
      end if;
      Read_String (What & " " & To_String (From_U) & " with: ", "", To_U, Ok,
                   History => (if Regexp then "replace-regexp-to" else "replace-to"));
      if not Ok then
         return;
      end if;

      declare
         From : constant String := To_String (From_U);
         To   : constant String := To_String (To_U);
         Fold : constant Boolean :=
           (if Regexp then Regex_Search.Folds (From) else Folds (From));

         function Find_Next return Boolean is
         begin
            if Regexp then
               Found := Regex_Search.Search_Forward (B, From, P, Fold);
               if not Found.Found then
                  return False;
               end if;
               MS := Found.Groups (0).Start;
               ME := Found.Groups (0).Stop;
            else
               declare
                  R : constant Integer := Search_Forward (B, From, P, Fold);
               begin
                  if R < 0 then
                     return False;
                  end if;
                  MS := R;
                  ME := R + From'Length;
               end;
            end if;
            --  No empty match at the very end of the buffer
            return not (MS = ME and then MS >= Length (B) and then Length (B) > 0);
         end Find_Next;

         --  After an empty match go one further, or it would be found again
         procedure Continue_After (Pos : Natural) is
         begin
            P := (if MS = ME then Pos + 1 else Pos);
         end Continue_After;

         procedure Replace_Match is
            New_Text : constant String :=
              (if Regexp then Regex_Search.Expand (B, Found, To) else To);
         begin
            Delete (B, MS, ME);
            B.Point := MS;
            Insert (B, New_Text);
            Count := Count + 1;
            Continue_After (B.Point);
         end Replace_Match;
      begin
         --  As in Emacs, the mark stays where replacing started
         B.Mark := B.Point;
         B.Mark_Set := True;
         P := B.Point;

         Search_Loop :
         loop
            exit Search_Loop when P > Length (B) or else not Find_Next;
            B.Point := ME;

            if All_Rest then
               Replace_Match;
            else
               Ask_Loop :
               loop
                  Display.Set_Highlight (MS, ME);
                  K := Read_Key_Echo
                    ("Query replacing " & From & " with " & To
                     & ": (y, n, !, ., q) ", Cursor_At_End => True);
                  Display.Clear_Highlight;

                  if K.Meta or else K.Ctrl then
                     Unread (K);
                     exit Search_Loop;
                  end if;

                  case K.Code is
                     when Character'Pos ('y') | 32 =>
                        Replace_Match;
                        exit Ask_Loop;
                     when Character'Pos ('n') | Del =>
                        Continue_After (ME);
                        exit Ask_Loop;
                     when Character'Pos ('!') =>
                        All_Rest := True;
                        Replace_Match;
                        exit Ask_Loop;
                     when Character'Pos ('.') =>
                        Replace_Match;
                        exit Search_Loop;
                     when Character'Pos ('q') | Ret | Esc =>
                        exit Search_Loop;
                     when Ctl_G =>
                        Message ("Quit");
                        return;
                     when others =>
                        null;
                  end case;
               end loop Ask_Loop;
            end if;
         end loop Search_Loop;
      end;

      Message ("Replaced " & Img (Count) & (if Count = 1 then " occurrence" else " occurrences"));
   end Replace;

   procedure Query_Replace is
   begin
      Replace (Regexp => False, Query => True);
   end Query_Replace;

   procedure Query_Replace_Regexp is
   begin
      Replace (Regexp => True, Query => True);
   end Query_Replace_Regexp;

   procedure Replace_String is
   begin
      Replace (Regexp => False, Query => False);
   end Replace_String;

   procedure Replace_Regexp is
   begin
      Replace (Regexp => True, Query => False);
   end Replace_Regexp;

   procedure Register_All is
   begin
      Register ("isearch_forward", Isearch_Forward'Access);
      Register ("isearch_backward", Isearch_Backward'Access);
      Register ("isearch_forward_regexp", Isearch_Forward_Regexp'Access);
      Register ("isearch_backward_regexp", Isearch_Backward_Regexp'Access);
      Register ("query_replace", Query_Replace'Access);
      Register ("query_replace_regexp", Query_Replace_Regexp'Access);
      Register ("replace_string", Replace_String'Access);
      Register ("replace_regexp", Replace_Regexp'Access);
   end Register_All;

end Search_Commands;
