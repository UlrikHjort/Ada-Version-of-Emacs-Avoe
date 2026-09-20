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

--  Keyboard input: decodes raw terminal bytes (UTF-8, escape sequences)
--  into key events.

package Keys is

   --  Control characters
   Ctl_Space      : constant := 0;
   Ctl_A          : constant := 1;
   Ctl_B          : constant := 2;
   Ctl_C          : constant := 3;
   Ctl_D          : constant := 4;
   Ctl_E          : constant := 5;
   Ctl_F          : constant := 6;
   Ctl_G          : constant := 7;
   Ctl_H          : constant := 8;
   Tab            : constant := 9;
   Ctl_J          : constant := 10;
   Ctl_K          : constant := 11;
   Ctl_L          : constant := 12;
   Ret            : constant := 13;
   Ctl_N          : constant := 14;
   Ctl_O          : constant := 15;
   Ctl_P          : constant := 16;
   Ctl_Q          : constant := 17;
   Ctl_R          : constant := 18;
   Ctl_S          : constant := 19;
   Ctl_T          : constant := 20;
   Ctl_U          : constant := 21;
   Ctl_V          : constant := 22;
   Ctl_W          : constant := 23;
   Ctl_X          : constant := 24;
   Ctl_Y          : constant := 25;
   Ctl_Z          : constant := 26;
   Esc            : constant := 27;
   Ctl_Underscore : constant := 31;
   Del            : constant := 127;

   --  Special keys live above the Unicode range
   Key_None      : constant := 16#11_0000#;
   Key_Resize    : constant := 16#11_0001#;
   Key_Up        : constant := 16#11_0010#;
   Key_Down      : constant := 16#11_0011#;
   Key_Left      : constant := 16#11_0012#;
   Key_Right     : constant := 16#11_0013#;
   Key_Home      : constant := 16#11_0014#;
   Key_End       : constant := 16#11_0015#;
   Key_Page_Up   : constant := 16#11_0016#;
   Key_Page_Down : constant := 16#11_0017#;
   Key_Insert    : constant := 16#11_0018#;
   Key_Delete    : constant := 16#11_0019#;

   type Key is record
      Code : Natural := Key_None;  --  Unicode code point or Key_*
      Meta : Boolean := False;
      Ctrl : Boolean := False;     --  Only used together with special keys
   end record;

   function Read_Key return Key;
   --  Blocks until a key arrives.  Returns Key_Resize when the terminal
   --  window changed size and Key_None for unrecognised sequences.

   procedure Unread (K : Key);
   --  Make K the next key returned by Read_Key.

   --  Keyboard macros.  While recording, every key read from the terminal
   --  is added to the macro being defined (keys given back with Unread are
   --  not added twice).  While a macro plays, Read_Key returns its keys
   --  before reading the terminal.

   procedure Start_Recording;
   procedure Stop_Recording (Keep : Natural);
   --  The first Keep recorded keys become the last macro.
   function Recording return Boolean;
   function Recorded_Count return Natural;
   function Have_Macro return Boolean;

   procedure Play_Macro;
   --  Queue the keys of the last macro.
   function Playing return Boolean;
   procedure Cancel_Playback;

   function Key_Pending return Boolean;
   --  A key was given back with Unread or a macro is playing: Read_Key
   --  will not wait for the terminal.

   function Is_Self_Inserting (K : Key) return Boolean;

   function Encode_UTF8 (Code : Natural) return String;

   function Describe (K : Key) return String;
   --  Emacs style key name, e.g. "C-x", "M-f", "<up>".

end Keys;
