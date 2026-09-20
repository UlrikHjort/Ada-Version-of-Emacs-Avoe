-- ***************************************************************************
--                           Avoe - Scripts.Values
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

--  Run-time values of Avoe script.
--
--  Vectors and records have value semantics.  Their items are shared behind
--  a reference count and copied only when a shared value is changed, so
--  passing and assigning them is cheap.

with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with String_Vectors;

package Scripts.Values is

   type Value_Kind is
     (V_None, V_Integer, V_Boolean, V_Character, V_String, V_Vector, V_Record);

   type Items_Data;
   type Items_Access is access Items_Data;

   type Items_Ref is new Ada.Finalization.Controlled with record
      Data : Items_Access;
   end record;

   overriding procedure Adjust (R : in out Items_Ref);
   overriding procedure Finalize (R : in out Items_Ref);

   type Value (Kind : Value_Kind := V_None) is record
      case Kind is
         when V_None              => null;
         when V_Integer           => Int   : Long_Long_Integer;
         when V_Boolean           => Bool  : Boolean;
         when V_Character         => Char  : Character;
         when V_String            => Str   : Unbounded_String;
         when V_Vector | V_Record => Items : Items_Ref;
      end case;
   end record;

   package Value_Vectors is new Ada.Containers.Vectors (Positive, Value);

   type Items_Data is record
      Count  : Natural := 1;               --  References to this data
      Values : Value_Vectors.Vector;
      Names  : String_Vectors.Vector;      --  Field names of a record
   end record;

   None : constant Value := (Kind => V_None);

   function Make_Int (N : Long_Long_Integer) return Value is ((Kind => V_Integer, Int => N));
   function Make_Bool (B : Boolean) return Value is ((Kind => V_Boolean, Bool => B));
   function Make_Char (C : Character) return Value is ((Kind => V_Character, Char => C));
   function Make_Str (S : String) return Value is
     ((Kind => V_String, Str => To_Unbounded_String (S)));

   --  Vectors (1-based) and records (named fields, in order)
   function Make_Vector return Value;
   function Make_Record return Value;
   function Item_Count (V : Value) return Natural;
   function Element (V : Value; Index : Positive) return Value;
   procedure Replace_Element (V : in out Value; Index : Positive; Item : Value);
   procedure Append (V : in out Value; Item : Value);
   procedure Prepend (V : in out Value; Item : Value);
   procedure Delete (V : in out Value; Index : Positive; Count : Positive := 1);
   function Vector_Slice (V : Value; From, To : Positive) return Value;
   function Find_Field (V : Value; Name : String) return Natural;
   --  0 if the record has no such field
   function Field_Name (V : Value; Index : Positive) return String;
   procedure Set_Field (V : in out Value; Name : String; Item : Value);
   --  Adds the field if it is new.

   function Equal (A, B : Value) return Boolean;
   --  Deep equality; record fields may be in any order.

   --  Declared types
   type Type_Name is
     (T_Any, T_Integer, T_Natural, T_Positive, T_Boolean, T_Character, T_String, T_Vector);

   function Type_Of_Name (Name : String; Found : out Boolean) return Type_Name;
   function Accepts (T : Type_Name; V : Value) return Boolean;
   function Type_Image (T : Type_Name) return String;
   function Kind_Name (V : Value) return String;

   function To_Display (V : Value) return String;
   --  Plain text: 42, True, x, text, [1, 2], (x => 1)
   function Ada_Image (V : Value) return String;
   --  Like Ada's 'Image: " 42", TRUE, 'x'
   function Literal_Image (V : Value) return String;
   --  As a literal: 42, True, 'x', "text", ["a", "b"]

end Scripts.Values;
