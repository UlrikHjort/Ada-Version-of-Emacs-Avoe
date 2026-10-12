with Interfaces; use Interfaces;

package body File_Modes is

   subtype Bits is Unsigned_32;        --  Ada's and/or need a modular type

   Set_User  : constant Bits := 8#4000#;
   Set_Group : constant Bits := 8#2000#;
   Sticky    : constant Bits := 8#1000#;
   All_Perms : constant Bits := 8#777#;

   function Image (Mode : Natural) return String is
      M : constant Bits := Bits (Mode);
      R : String := "---------";

      --  One triad of rwx: At_Index is 1, 4 or 7, Shift the octal digit
      procedure Triad (At_Index : Positive; Shift : Natural;
                       Special : Character; Special_Set : Boolean)
      is
         Three : constant Bits := (M / (8 ** Shift)) mod 8;
      begin
         if (Three and 4) /= 0 then
            R (At_Index) := 'r';
         end if;
         if (Three and 2) /= 0 then
            R (At_Index + 1) := 'w';
         end if;
         if (Three and 1) /= 0 then
            R (At_Index + 2) := 'x';
         end if;
         if Special_Set then
            --  Lower case when the file is executable too, upper case if not
            R (At_Index + 2) :=
              (if (Three and 1) /= 0 then Special
               else Character'Val (Character'Pos (Special) - 32));
         end if;
      end Triad;
   begin
      Triad (1, 2, 's', (M and Set_User) /= 0);
      Triad (4, 1, 's', (M and Set_Group) /= 0);
      Triad (7, 0, 't', (M and Sticky) /= 0);
      return R;
   end Image;

   function Octal (Mode : Natural) return String is
      Digit   : constant String := "01234567";
      Special : constant Natural := (Mode / 8#1000#) mod 8;
      R       : String (1 .. 3);
      M       : Natural := Mode mod 8#1000#;
   begin
      for I in reverse R'Range loop
         R (I) := Digit (M mod 8 + 1);
         M := M / 8;
      end loop;
      return (if Special = 0 then R else Digit (Special + 1) & R);
   end Octal;

   procedure Parse
     (Text         : String;
      Current      : Natural;
      Is_Directory : Boolean;
      Result       : out Natural;
      Ok           : out Boolean)
   is
      Mode : Bits := Bits (Current);
      I    : Positive;

      --  One clause: [ugoa]* [-+=] [rwxXst]*
      procedure Clause (From, To : Natural; Good : out Boolean) is
         Who      : Bits := 0;      --  Permission bits this clause may touch
         Special  : Bits := 0;      --  Special bits this clause may touch
         Value    : Bits := 0;      --  r, w, x as one octal digit
         Specials : Bits := 0;      --  The special bits to set
         Op       : Character;
         J        : Natural := From;
      begin
         Good := False;
         while J <= To and then Text (J) in 'u' | 'g' | 'o' | 'a' loop
            case Text (J) is
               when 'u' => Who := Who or 8#700#; Special := Special or Set_User;
               when 'g' => Who := Who or 8#070#; Special := Special or Set_Group;
               when 'o' => Who := Who or 8#007#; Special := Special or Sticky;
               when others =>
                  Who := All_Perms;
                  Special := Set_User or Set_Group or Sticky;
            end case;
            J := J + 1;
         end loop;
         if Who = 0 then               --  No who given means all of them
            Who := All_Perms;
            Special := Set_User or Set_Group or Sticky;
         end if;

         if J > To or else Text (J) not in '+' | '-' | '=' then
            return;
         end if;
         Op := Text (J);
         J := J + 1;

         while J <= To loop
            case Text (J) is
               when 'r' => Value := Value or 4;
               when 'w' => Value := Value or 2;
               when 'x' => Value := Value or 1;
               when 'X' =>
                  --  Only for directories, or files already executable
                  if Is_Directory or else (Bits (Current) and 8#111#) /= 0 then
                     Value := Value or 1;
                  end if;
               when 's' => Specials := Specials or (Special and (Set_User or Set_Group));
               when 't' => Specials := Specials or (Special and Sticky);
               when others => return;
            end case;
            J := J + 1;
         end loop;

         declare
            Touched : constant Bits :=
              ((Value * 8#100#) or (Value * 8#010#) or Value) and Who;
         begin
            case Op is
               when '+'    => Mode := Mode or Touched or Specials;
               when '-'    => Mode := Mode and not (Touched or Specials);
               when others => Mode := (Mode and not (Who or Special)) or Touched or Specials;
            end case;
         end;
         Good := True;
      end Clause;

   begin
      Result := Current;
      Ok := False;
      if Text'Length = 0 then
         return;
      end if;

      --  An octal number sets every bit at once
      if (for all C of Text => C in '0' .. '7') then
         if Text'Length > 4 then
            return;
         end if;
         Mode := 0;
         for C of Text loop
            Mode := Mode * 8 + Bits (Character'Pos (C) - Character'Pos ('0'));
         end loop;
         Result := Natural (Mode);
         Ok := True;
         return;
      end if;

      I := Text'First;
      loop
         declare
            Stop : Natural := I - 1;
            Good : Boolean;
         begin
            while Stop < Text'Last and then Text (Stop + 1) /= ',' loop
               Stop := Stop + 1;
            end loop;
            if Stop < I then            --  An empty clause, as in "u+x,,g-w"
               return;
            end if;
            Clause (I, Stop, Good);
            if not Good then
               return;
            end if;
            exit when Stop >= Text'Last;
            I := Stop + 2;
            if I > Text'Last then       --  A trailing comma
               return;
            end if;
         end;
      end loop;

      Result := Natural (Mode);
      Ok := True;
   end Parse;

end File_Modes;
