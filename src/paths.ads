-- ***************************************************************************
--                                Avoe - Paths
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

--  Where avoe finds its files, following the FHS for installed files and
--  the XDG base directory specification for per-user files.
--
--  Installed (relative to the executable, so any PREFIX works):
--    PREFIX/bin/avoe
--    PREFIX/share/avoe/*.avoe         bundled scripts ($AVOE_DATA_DIR)
--    PREFIX/etc/avoe/site.avoe        site configuration, or /etc/avoe/site.avoe
--  Per user:
--    $XDG_CONFIG_HOME/avoe/scripts/*.avoe   (default ~/.config/avoe)
--    $XDG_CONFIG_HOME/avoe/init.avoe, or ~/.avoerc
--    $XDG_STATE_HOME/avoe                   (default ~/.local/state/avoe)

with String_Vectors;

package Paths is

   function Executable return String;
   function Prefix return String;
   --  The directory above the executable's bin directory ("" if unknown).

   function Data_Directory return String;
   function Site_Config_Candidates return String_Vectors.Vector;
   function Site_Config_File return String;
   --  The first candidate that exists, or "".

   function Config_Directory return String;
   function User_Scripts_Directory return String;
   function Init_File_Candidates return String_Vectors.Vector;
   function Init_File return String;
   --  The first candidate that exists, or "".

   function State_Directory return String;

   function Script_Files (Directory : String) return String_Vectors.Vector;
   --  The *.avoe files in Directory, sorted by name.

   procedure Print_Report;
   --  Show all locations and whether they exist (avoe --paths).

end Paths;
