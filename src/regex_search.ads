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

--  Regular expression search in buffers (using GNAT.Regpat, Perl-like
--  syntax).  Matching is done line by line, so a match never spans lines;
--  ^ and $ match at line boundaries.

with Buffers; use Buffers;

package Regex_Search is

   Invalid_Pattern : exception;
   --  Raised with a short explanation if a pattern is not valid.

   Max_Groups : constant := 9;

   type Group is record
      Matched : Boolean := False;
      Start   : Natural := 0;   --  Buffer positions [Start, Stop)
      Stop    : Natural := 0;
   end record;

   type Group_Array is array (0 .. Max_Groups) of Group;

   type Match_Result is record
      Found  : Boolean := False;
      Groups : Group_Array;      --  Groups (0) is the whole match
   end record;

   function Folds (Pattern : String) return Boolean;
   --  True if the pattern has no upper-case letters (outside escapes such
   --  as \S), meaning the search should ignore case.

   procedure Check (Pattern : String);
   --  Raise Invalid_Pattern if Pattern does not compile.

   function Search_Forward
     (B : Buffer; Pattern : String; From : Natural; Fold : Boolean) return Match_Result;
   --  The first match starting at or after From.

   function Search_Backward
     (B : Buffer; Pattern : String; From : Integer; Fold : Boolean) return Match_Result;
   --  The last match starting at or before From.

   function Expand (B : Buffer; M : Match_Result; Replacement : String) return String;
   --  Replacement with \1 .. \9 replaced by the groups, \& by the whole
   --  match and \\ by a backslash.

end Regex_Search;
