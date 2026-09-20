-- ***************************************************************************
--                                Avoe - Modes
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

--  Major modes: choosing a mode from the file name, mode hooks, mode
--  commands and the default mode keymaps.

with Buffers; use Buffers;

package Modes is

   function Mode_For_File (File_Name : String) return Mode_Kind;
   --  .adb .ads .ada .gpr -> Ada; .avoe and .avoerc -> Avoe script.

   function Mode_Of_Name (Name : String; Found : out Boolean) return Mode_Kind;
   --  "fundamental", "ada", "script" (or "avoe_script"), "compilation"

   procedure Set_Mode (B : Buffer_Access; Mode : Mode_Kind);
   --  Also runs the command <mode>_mode_hook (e.g. ada_mode_hook) if a
   --  script defined one.

   procedure Register_All;

end Modes;
