-- ***************************************************************************
--                               Avoe - Keymaps
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
with Ada.Strings.Fixed;
with Commands;
with Utils;

package body Keymaps is

   Global : constant Keymap_Access := new Keymap;

   function Global_Map return Keymap_Access is (Global);

   package Map_Vectors is new Ada.Containers.Vectors (Positive, Keymap_Access);

   Mode_Maps : Map_Vectors.Vector;

   --  Created on first use, so modes defined by scripts get one too
   function Mode_Map (Mode : Buffers.Mode_Kind) return Keymap_Access is
   begin
      while Mode_Maps.Last_Index < Mode loop
         Mode_Maps.Append (null);
      end loop;
      if Mode_Maps (Mode) = null then
         Mode_Maps.Replace_Element (Mode, new Keymap);
      end if;
      return Mode_Maps (Mode);
   end Mode_Map;

   --  A key as a map index: the code point with the two modifier bits
   function Encode (K : Key) return Natural is
     (K.Code * 4 + (if K.Meta then 2 else 0) + (if K.Ctrl then 1 else 0));

   function Decode (N : Natural) return Key is
     (Code => N / 4, Meta => (N / 2) mod 2 = 1, Ctrl => N mod 2 = 1);

   function Lookup (Map : Keymap_Access; K : Key) return Binding is
      use Binding_Maps;
      C : constant Cursor := Map.Entries.Find (Encode (K));
   begin
      if Has_Element (C) then
         return Element (C);
      end if;
      --  As in Emacs, an unbound M-F runs what M-f runs
      if K.Meta and then K.Code in Character'Pos ('A') .. Character'Pos ('Z') then
         return Lookup (Map, (Code => K.Code + 32, Meta => True, Ctrl => K.Ctrl));
      end if;
      return (Kind => Unbound, Name => Null_Unbounded_String, Map => null);
   end Lookup;

   function Parse_One (Token : String) return Key is
      Meta : Boolean := False;
      Ctrl : Boolean := False;
      I    : Positive := Token'First;
      Code : Natural;
   begin
      while Token'Last - I >= 2
        and then Token (I + 1) = '-'
        and then Token (I) in 'C' | 'M'
      loop
         if Token (I) = 'C' then
            Ctrl := True;
         else
            Meta := True;
         end if;
         I := I + 2;
      end loop;

      declare
         Base : constant String := Token (I .. Token'Last);
      begin
         if Base = "SPC" then
            Code := 32;
         elsif Base = "TAB" then
            Code := Keys.Tab;
         elsif Base = "RET" then
            Code := Keys.Ret;
         elsif Base = "ESC" then
            Code := Keys.Esc;
         elsif Base = "DEL" then
            Code := Keys.Del;
         elsif Base = "<up>" then
            Code := Key_Up;
         elsif Base = "<down>" then
            Code := Key_Down;
         elsif Base = "<left>" then
            Code := Key_Left;
         elsif Base = "<right>" then
            Code := Key_Right;
         elsif Base = "<home>" then
            Code := Key_Home;
         elsif Base = "<end>" then
            Code := Key_End;
         elsif Base = "<prior>" then
            Code := Key_Page_Up;
         elsif Base = "<next>" then
            Code := Key_Page_Down;
         elsif Base = "<insert>" then
            Code := Key_Insert;
         elsif Base = "<delete>" then
            Code := Key_Delete;
         elsif Base'Length > 0 and then Utils.Cell_Count (Base) = 1 then
            Code := Utils.Decode_First (Base);
         else
            raise Parse_Error with "bad key: " & Token;
         end if;
      end;

      --  C- with a character is the ASCII control character the terminal
      --  sends; only special keys such as C-<right> keep a Ctrl flag
      if not Ctrl then
         return (Code => Code, Meta => Meta, Ctrl => False);
      elsif Code >= Key_Up then
         return (Code => Code, Meta => Meta, Ctrl => True);
      end if;

      case Code is
         when Character'Pos ('a') .. Character'Pos ('z') => Code := Code - 96;
         when Character'Pos ('A') .. Character'Pos ('Z') => Code := Code - 64;
         when Character'Pos ('@') | 32                   => Code := 0;
         when Character'Pos ('[')                        => Code := 27;
         when Character'Pos ('\')                        => Code := 28;
         when Character'Pos (']')                        => Code := 29;
         when Character'Pos ('^')                        => Code := 30;
         when Character'Pos ('_') | Character'Pos ('/')  => Code := 31;
         when Character'Pos ('?')                        => Code := 127;
         when others =>
            raise Parse_Error with "bad control key: " & Token;
      end case;
      return (Code => Code, Meta => Meta, Ctrl => False);
   end Parse_One;

   function Parse (Sequence : String) return Key_Array is
      use Ada.Strings.Fixed;
      S     : constant String := Trim (Sequence, Ada.Strings.Both);
      Space : constant Natural := Index (S, " ");
   begin
      if S = "" then
         raise Parse_Error with "empty key sequence";
      elsif Space = 0 then
         return (1 => Parse_One (S));
      else
         return Parse_One (S (S'First .. Space - 1)) & Parse (S (Space + 1 .. S'Last));
      end if;
   end Parse;

   function Describe (Seq : Key_Array) return String is
   begin
      if Seq'Length = 0 then
         return "";
      elsif Seq'Length = 1 then
         return Keys.Describe (Seq (Seq'First));
      else
         return Keys.Describe (Seq (Seq'First)) & " "
           & Describe (Seq (Seq'First + 1 .. Seq'Last));
      end if;
   end Describe;

   --  Every key but the last leads into a prefix map, which is created when
   --  missing (replacing a command bound to that key)
   procedure Bind (Map : Keymap_Access; Sequence : String; Command_Name : String) is
      Seq : constant Key_Array := Parse (Sequence);
      M   : Keymap_Access := Map;
   begin
      for I in Seq'Range loop
         declare
            Code : constant Natural := Encode (Seq (I));
            C    : constant Binding_Maps.Cursor := M.Entries.Find (Code);
         begin
            if I = Seq'Last then
               M.Entries.Include
                 (Code, (Kind => Command,
                         Name => To_Unbounded_String (Commands.Normalize (Command_Name)),
                         Map  => null));
            elsif Binding_Maps.Has_Element (C)
              and then Binding_Maps.Element (C).Kind = Prefix
            then
               M := Binding_Maps.Element (C).Map;
            else
               declare
                  Sub : constant Keymap_Access := new Keymap;
               begin
                  M.Entries.Include
                    (Code, (Kind => Prefix, Name => Null_Unbounded_String, Map => Sub));
                  M := Sub;
               end;
            end if;
         end;
      end loop;
   end Bind;

   procedure For_Each_Binding
     (Map     : Keymap_Access;
      Process : not null access procedure (Sequence, Command_Name : String))
   is
      procedure Walk (M : Keymap_Access; Prefix_Text : String) is
      begin
         for C in M.Entries.Iterate loop
            declare
               Text : constant String :=
                 Prefix_Text & Keys.Describe (Decode (Binding_Maps.Key (C)));
               B    : constant Binding := Binding_Maps.Element (C);
            begin
               case B.Kind is
                  when Command => Process (Text, To_String (B.Name));
                  when Prefix  => Walk (B.Map, Text & " ");
                  when Unbound => null;
               end case;
            end;
         end loop;
      end Walk;
   begin
      Walk (Map, "");
   end For_Each_Binding;

   --  The shortest key sequence for a command, or "" if it has none
   function Where_Is (Map : Keymap_Access; Command_Name : String) return String is
      Wanted : constant String := Commands.Normalize (Command_Name);
      Best   : Unbounded_String;

      procedure Check (Sequence, Name : String) is
      begin
         if Name = Wanted
           and then (Best = Null_Unbounded_String or else Sequence'Length < Length (Best))
         then
            Best := To_Unbounded_String (Sequence);
         end if;
      end Check;
   begin
      For_Each_Binding (Map, Check'Access);
      return To_String (Best);
   end Where_Is;

end Keymaps;
