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

--  Keymaps: key sequences bound to command names.  Prefix keys such as
--  C-x lead to nested keymaps.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Buffers;
with Keys;                  use Keys;

private with Ada.Containers.Ordered_Maps;

package Keymaps is

   Parse_Error : exception;

   type Keymap is limited private;
   type Keymap_Access is access Keymap;

   type Binding_Kind is (Unbound, Command, Prefix);

   type Binding is record
      Kind : Binding_Kind := Unbound;
      Name : Unbounded_String;      --  Command
      Map  : Keymap_Access;         --  Prefix
   end record;

   type Key_Array is array (Positive range <>) of Key;

   function Global_Map return Keymap_Access;

   function Mode_Map (Mode : Buffers.Mode_Kind) return Keymap_Access;
   --  Bindings that apply only in buffers of that mode; they take
   --  precedence over the global map.

   function Lookup (Map : Keymap_Access; K : Key) return Binding;

   procedure Bind (Map : Keymap_Access; Sequence : String; Command_Name : String);
   --  Sequence in Emacs notation, e.g. "C-x C-f", "M-%", "<up>".

   function Parse (Sequence : String) return Key_Array;
   function Describe (Seq : Key_Array) return String;

   procedure For_Each_Binding
     (Map     : Keymap_Access;
      Process : not null access procedure (Sequence, Command_Name : String));

   function Where_Is (Map : Keymap_Access; Command_Name : String) return String;
   --  The shortest key sequence running the command, or "".

private

   package Binding_Maps is new Ada.Containers.Ordered_Maps (Natural, Binding);

   type Keymap is record
      Entries : Binding_Maps.Map;
   end record;

end Keymaps;
