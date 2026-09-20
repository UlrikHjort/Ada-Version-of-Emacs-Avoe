-- ***************************************************************************
--                              Avoe - Commands
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

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Fixed;
with Utils;

package body Commands is

   type Info is record
      Proc       : Command_Proc;
      Repeatable : Boolean := False;
      Is_Script  : Boolean := False;
   end record;

   --  Ordered, so that completion lists command names alphabetically
   package Info_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Info);

   Registry : Info_Maps.Map;

   function Normalize (Name : String) return String is
      R : String := Ada.Strings.Fixed.Trim (Name, Ada.Strings.Both);
   begin
      for C of R loop
         C := (if C = '-' then '_' else Utils.To_Lower (C));
      end loop;
      return R;
   end Normalize;

   procedure Register
     (Name       : String;
      Proc       : Command_Proc;
      Repeatable : Boolean := False) is
   begin
      Registry.Include (Normalize (Name), (Proc, Repeatable, Is_Script => False));
   end Register;

   procedure Register_Script (Name : String) is
   begin
      Registry.Include (Normalize (Name), (null, False, Is_Script => True));
   end Register_Script;

   function Exists (Name : String) return Boolean is
     (Registry.Contains (Normalize (Name)));

   function Is_Repeatable (Name : String) return Boolean is
     (Exists (Name) and then Registry.Element (Normalize (Name)).Repeatable);

   procedure Run (Name : String) is
      N : constant String := Normalize (Name);
   begin
      if not Registry.Contains (N) then
         raise Unknown_Command with N;
      end if;
      declare
         I : constant Info := Registry.Element (N);
      begin
         --  Script commands have no procedure: the interpreter runs the
         --  script procedure of that name
         if I.Is_Script then
            if Run_Script_Command /= null then
               Run_Script_Command (N);
            end if;
         else
            I.Proc.all;
         end if;
      end;
   end Run;

   function Complete (Input : String) return String_Vectors.Vector is
      Prefix : constant String := Normalize (Input);
      Result : String_Vectors.Vector;
   begin
      for C in Registry.Iterate loop
         if Utils.Starts_With (Info_Maps.Key (C), Prefix) then
            Result.Append (Info_Maps.Key (C));
         end if;
      end loop;
      return Result;
   end Complete;

end Commands;
