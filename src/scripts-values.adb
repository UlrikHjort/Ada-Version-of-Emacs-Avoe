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

with Ada.Containers;
with Ada.Unchecked_Deallocation;

package body Scripts.Values is

   procedure Free is new Ada.Unchecked_Deallocation (Items_Data, Items_Access);

   --  Copies of a vector or record share its items and count references.
   --  The items are only copied when a shared value is changed, see
   --  Make_Unique, so passing vectors around is cheap.

   overriding procedure Adjust (R : in out Items_Ref) is
   begin
      if R.Data /= null then
         R.Data.Count := R.Data.Count + 1;
      end if;
   end Adjust;

   overriding procedure Finalize (R : in out Items_Ref) is
      D : Items_Access := R.Data;
   begin
      R.Data := null;   --  Finalize can be called more than once
      if D /= null then
         D.Count := D.Count - 1;
         if D.Count = 0 then
            Free (D);
         end if;
      end if;
   end Finalize;

   --  Give V its own copy of shared items before changing them
   procedure Make_Unique (V : in out Value) is
   begin
      if V.Items.Data.Count > 1 then
         V.Items.Data.Count := V.Items.Data.Count - 1;
         V.Items.Data := new Items_Data'(Count  => 1,
                                         Values => V.Items.Data.Values,
                                         Names  => V.Items.Data.Names);
      end if;
   end Make_Unique;

   function Make_Vector return Value is
     ((Kind  => V_Vector,
       Items => (Ada.Finalization.Controlled with Data => new Items_Data)));

   function Make_Record return Value is
     ((Kind  => V_Record,
       Items => (Ada.Finalization.Controlled with Data => new Items_Data)));

   function Item_Count (V : Value) return Natural is (Natural (V.Items.Data.Values.Length));

   function Element (V : Value; Index : Positive) return Value is
     (V.Items.Data.Values (Index));

   procedure Replace_Element (V : in out Value; Index : Positive; Item : Value) is
   begin
      Make_Unique (V);
      V.Items.Data.Values.Replace_Element (Index, Item);
   end Replace_Element;

   procedure Append (V : in out Value; Item : Value) is
   begin
      Make_Unique (V);
      V.Items.Data.Values.Append (Item);
   end Append;

   procedure Prepend (V : in out Value; Item : Value) is
   begin
      Make_Unique (V);
      V.Items.Data.Values.Prepend (Item);
   end Prepend;

   procedure Delete (V : in out Value; Index : Positive; Count : Positive := 1) is
   begin
      Make_Unique (V);
      V.Items.Data.Values.Delete (Index, Ada.Containers.Count_Type (Count));
   end Delete;

   function Vector_Slice (V : Value; From, To : Positive) return Value is
      Result : constant Value := Make_Vector;  --  Its items are changed through an access
   begin
      for I in From .. To loop
         Result.Items.Data.Values.Append (Element (V, I));
      end loop;
      return Result;
   end Vector_Slice;

   function Find_Field (V : Value; Name : String) return Natural is
     (V.Items.Data.Names.Find_Index (Name));

   function Field_Name (V : Value; Index : Positive) return String is
     (V.Items.Data.Names (Index));

   procedure Set_Field (V : in out Value; Name : String; Item : Value) is
      I : constant Natural := Find_Field (V, Name);
   begin
      Make_Unique (V);
      if I = 0 then
         V.Items.Data.Names.Append (Name);
         V.Items.Data.Values.Append (Item);
      else
         V.Items.Data.Values.Replace_Element (I, Item);
      end if;
   end Set_Field;

   function Equal (A, B : Value) return Boolean is
   begin
      if A.Kind /= B.Kind then
         return False;
      end if;
      case A.Kind is
         when V_None      => return True;
         when V_Integer   => return A.Int = B.Int;
         when V_Boolean   => return A.Bool = B.Bool;
         when V_Character => return A.Char = B.Char;
         when V_String    => return A.Str = B.Str;
         when V_Vector =>
            if Item_Count (A) /= Item_Count (B) then
               return False;
            end if;
            for I in 1 .. Item_Count (A) loop
               if not Equal (Element (A, I), Element (B, I)) then
                  return False;
               end if;
            end loop;
            return True;
         when V_Record =>
            --  The same fields with equal values, in any order
            if Item_Count (A) /= Item_Count (B) then
               return False;
            end if;
            for I in 1 .. Item_Count (A) loop
               declare
                  J : constant Natural := Find_Field (B, Field_Name (A, I));
               begin
                  if J = 0 or else not Equal (Element (A, I), Element (B, J)) then
                     return False;
                  end if;
               end;
            end loop;
            return True;
      end case;
   end Equal;

   function Type_Of_Name (Name : String; Found : out Boolean) return Type_Name is
   begin
      Found := True;
      if Name = "integer" then
         return T_Integer;
      elsif Name = "natural" then
         return T_Natural;
      elsif Name = "positive" then
         return T_Positive;
      elsif Name = "boolean" then
         return T_Boolean;
      elsif Name = "character" then
         return T_Character;
      elsif Name = "string" then
         return T_String;
      elsif Name = "vector" then
         return T_Vector;
      end if;
      Found := False;
      return T_Any;
   end Type_Of_Name;

   function Accepts (T : Type_Name; V : Value) return Boolean is
     (case T is
         when T_Any       => True,
         when T_Integer   => V.Kind = V_Integer,
         when T_Natural   => V.Kind = V_Integer and then V.Int >= 0,
         when T_Positive  => V.Kind = V_Integer and then V.Int >= 1,
         when T_Boolean   => V.Kind = V_Boolean,
         when T_Character => V.Kind = V_Character,
         when T_String    => V.Kind = V_String,
         when T_Vector    => V.Kind = V_Vector);

   function Type_Image (T : Type_Name) return String is
     (case T is
         when T_Any       => "any type",
         when T_Integer   => "Integer",
         when T_Natural   => "Natural",
         when T_Positive  => "Positive",
         when T_Boolean   => "Boolean",
         when T_Character => "Character",
         when T_String    => "String",
         when T_Vector    => "Vector");

   function Kind_Name (V : Value) return String is
     (case V.Kind is
         when V_None      => "no value",
         when V_Integer   => "Integer",
         when V_Boolean   => "Boolean",
         when V_Character => "Character",
         when V_String    => "String",
         when V_Vector    => "Vector",
         when V_Record    => "Record");

   function Int_Image (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Int_Image;

   function Composite_Image (V : Value) return String is
      R : Unbounded_String;
   begin
      Append (R, (if V.Kind = V_Vector then "[" else "("));
      for I in 1 .. Item_Count (V) loop
         if I > 1 then
            Append (R, ", ");
         end if;
         if V.Kind = V_Record then
            Append (R, Field_Name (V, I) & " => ");
         end if;
         Append (R, Literal_Image (Element (V, I)));
      end loop;
      Append (R, (if V.Kind = V_Vector then "]" else ")"));
      return To_String (R);
   end Composite_Image;

   --  Three ways to show a value: To_Display for messages (strings as they
   --  are), Ada_Image like Ada's 'Image (" 5", TRUE) and Literal_Image as
   --  it would be written in a script, which M-: shows

   function To_Display (V : Value) return String is
     (case V.Kind is
         when V_None              => "",
         when V_Integer           => Int_Image (V.Int),
         when V_Boolean           => (if V.Bool then "True" else "False"),
         when V_Character         => (1 => V.Char),
         when V_String            => To_String (V.Str),
         when V_Vector | V_Record => Composite_Image (V));

   function Ada_Image (V : Value) return String is
     (case V.Kind is
         when V_None              => "",
         when V_Integer           => Long_Long_Integer'Image (V.Int),
         when V_Boolean           => (if V.Bool then "TRUE" else "FALSE"),
         when V_Character         => "'" & V.Char & "'",
         when V_String            => To_String (V.Str),
         when V_Vector | V_Record => Composite_Image (V));

   function Literal_Image (V : Value) return String is
   begin
      case V.Kind is
         when V_String =>
            declare
               R : Unbounded_String := To_Unbounded_String ("""");
            begin
               for C of To_String (V.Str) loop
                  if C = '"' then
                     Append (R, """""");
                  else
                     Append (R, C);
                  end if;
               end loop;
               Append (R, '"');
               return To_String (R);
            end;
         when V_Character =>
            return "'" & V.Char & "'";
         when others =>
            return To_Display (V);
      end case;
   end Literal_Image;

end Scripts.Values;
