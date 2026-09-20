-- ***************************************************************************
--                            Avoe - Version_Info
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

--  The version and credits shown by avoe --version, the startup screen and
--  M-x about_avoe.  Keep Number in step with alire.toml (a test checks).

package Version_Info is

   Name        : constant String := "avoe";
   Number      : constant String := "1.0.0";
   Title       : constant String := "Ada Version Of Emacs";
   Description : constant String := "A small Emacs-like editor for the terminal, written in Ada.";
   Author      : constant String := "Ulrik Hørlyk Hjort";
   Year        : constant String := "2026";
   Homepage    : constant String := "https://github.com/UlrikHjort/Ada-Version-of-Emacs-Avoe";

end Version_Info;
