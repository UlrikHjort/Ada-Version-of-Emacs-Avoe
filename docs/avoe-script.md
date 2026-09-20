# Avoe script

Avoe's extension language looks like Ada but is lighter:

- **Kept from Ada:** block syntax, case-insensitive names, named and default
  parameters, `in out` parameters, `Natural`/`Positive` range checks,
  constants, attributes, and no implicit conversions.
- **Relaxed:** declarations are optional, values carry their type at run
  time, and there are no `with` clauses, packages, generics or tasks.

Scripts run from your init file `~/.config/avoe/init.avoe` (or `~/.avoerc`) at startup, with `M-:` (eval_expression),
`M-x load_file`, `M-x eval_buffer`, `M-x eval_region`, or without a terminal:

    avoe --batch script.avoe [file ...]

Errors report `file:line:column: message`. C-g interrupts a running script.

## A taste

```ada
--  Duplicate the current line (bound to C-c d)
procedure Duplicate_Line is
   pragma Command;
   Text   : constant String  := Current_Line;
   Offset : constant Natural := Point - Line_Beginning_Position;
begin
   End_Of_Line;
   Insert (LF & Text);
   Goto_Char (Line_Beginning_Position + Offset);
end Duplicate_Line;

Bind_Key ("C-c d", "duplicate_line");
```

See `examples/avoerc.avoe` for more.

## Values and types

| Type        | Literals               | Notes                              |
|-------------|------------------------|------------------------------------|
| `Integer`   | `42`, `1_000`, `16#FF#` | 64-bit, overflow is an error       |
| `Natural`, `Positive` | | Integer with a range check          |
| `Boolean`   | `True`, `False`        |                                    |
| `Character` | `'a'`, `LF`, `HT`, `CR`, `NUL` | one byte                   |
| `String`    | `"text"`, `"say ""hi"""` | 1-based, byte indexed            |

There are no implicit conversions: `1 + "2"` is an error. Convert explicitly
with `Integer'Image`, `Integer'Value`, `Image (X)`, `Character'Val`, etc.

## Declarations and assignment

```ada
X := 5;                         --  no declaration needed
Count : Natural := 0;           --  typed: later assignments are checked
Name  : constant String := "Avoe";
Max   : constant := 100;
A, B  : Integer := 0;
```

Variables assigned at the outermost level are global. Inside a subprogram,
assigning to a name that isn't a local or global variable creates a local one.

## Statements

```ada
if C then ... elsif C then ... else ... end if;
case X is when 1 | 2 => ...; when 3 .. 9 => ...; when others => ...; end case;
for I in 1 .. 10 loop ... end loop;
for I in reverse 1 .. 10 loop ... end loop;
while C loop ... end loop;
loop ... exit when C; ... end loop;
declare X : constant Integer := 1; begin ... end;
return;  return Value;  null;
```

## Expressions

Operators, loosest binding first:

| Operators                         |                                           |
|-----------------------------------|-------------------------------------------|
| `and` `or` `xor` `and then` `or else` | Boolean                               |
| `=` `/=` `<` `<=` `>` `>=` `in A .. B` `not in A .. B` | same-type operands |
| `+` `-` `&`                       | `&` joins Strings and Characters          |
| `*` `/` `mod` `rem`               |                                           |
| `**` `abs` `not`                  |                                           |

Unary minus binds more loosely than `mod`, as in Ada: `-7 mod 3 = -1`.

Conditional expression: `(if C then A elsif D then B else E)`.
String indexing and slices: `S (1)`, `S (2 .. 5)`.

Attributes:
- On values: `S'Length`, `S'First`, `S'Last`, `X'Image`.
- On types: `Integer'Image (X)`, `Integer'Value (S)`, `Integer'Min (A, B)`,
  `Integer'Max (A, B)`, `Integer'First`, `Integer'Last`, `Integer'Succ`,
  `Integer'Pred`, `Character'Val (N)`, `Character'Pos (C)`, `Boolean'Image`,
  `Boolean'Value`.

## Subprograms

```ada
function Greet (Who : String := "World"; Punct : Character := '!') return String is
begin
   return "Hello, " & Who & Punct;
end Greet;

procedure Swap (A, B : in out Integer) is
   T : constant Integer := A;
begin
   A := B;
   B := T;
end Swap;

Message (Greet (Punct => '?', Who => "Ada"));
```

- Parameter types are optional (`procedure P (X) is`).
- `in` parameters are constant.
- `out` and `in out` arguments must be variables.
- Subprograms are declared at the outermost level, and redefining one
  replaces it.

`pragma Command;` in the declarative part makes a parameterless procedure an
editor command. It is then available with `M-x` and bindable with `Bind_Key`.
If it has the same name as a built-in command, it replaces that command.
`pragma Command (Name);` after the body does the same.

## Calling editor commands

Every editor command is callable as a procedure, with an optional repeat
count:

```ada
Beginning_Of_Buffer;
Forward_Word (3);
Kill_Line;
Goto_Line (42);
Run_Command ("save_buffer");
```

`Editor.` may be used as a prefix: `Editor.Insert ("x");`.

## Built-in functions and procedures

Positions are 1-based: the buffer spans `Point_Min .. Point_Max`.

| Name | Returns | |
|------|---------|--|
| `Point`, `Point_Min`, `Point_Max`, `Buffer_Size` | Integer | |
| `Goto_Char (Position)` | | |
| `Insert (Text)` | | String or Character |
| `Delete_Region (From, To)` | | |
| `Buffer_Substring (From, To)`, `Buffer_Text` | String | |
| `Char_After (Position := Point)`, `Char_Before` | Character | `NUL` at the edges |
| `Current_Line` | String | without the newline |
| `Line_Beginning_Position`, `Line_End_Position` | Integer | |
| `Current_Column` | Integer | 0-based, tabs expanded |
| `Line_Number` | Integer | |
| `Looking_At (Text)` | Boolean | |
| `Search_Forward (Pattern, Ignore_Case := False)` | Boolean | moves point to the end of the match |
| `Search_Backward (Pattern, Ignore_Case := False)` | Boolean | moves point to the start of the match |
| `Mark`, `Region_Beginning`, `Region_End` | Integer | error if no mark |
| `Set_Mark (Position := Point)` | | |
| `Buffer_Name`, `File_Name` | String | |
| `Modified` | Boolean | |
| `Visit_File (Name)`, `Select_Buffer (Name)` | | |
| `Message (Item)` | | any value |
| `Read_String (Prompt, Default := "")` | String | C-g aborts the script |
| `Yes_Or_No (Prompt)` | Boolean | |
| `Bind_Key (Keys, Command)` | | e.g. `"C-c d"`, `"M-<up>"` |
| `Run_Command (Name, Count := 1)`, `Command_Exists (Name)` | | |
| `Set_Tab_Width (Width)` | | |
| `Upcase (Item)`, `Downcase (Item)` | String/Character | ASCII only |
| `Index (Source, Pattern, From := 1)` | Integer | 0 if not found |
| `Trim (Source)`, `Length (Source)`, `Image (Item)` | | Trim removes surrounding blanks, tabs and line breaks |
| `Getenv (Name)` | String | "" if unset |
| `Mode_Name` | String | "Ada", "Avoe-Script", ... |
| `Set_Mode (Mode)` | | "fundamental", "ada", "script", "compilation" |
| `Bind_Mode_Key (Mode, Keys, Command)` | | binding only in that mode |
| `Set_Face (Face, Code)` | | faces: keyword, type, comment, string, number, error, warning, status, paren (matching brackets); ANSI codes like "1;34" |
| `Set_Indent_Width (Width)` | | Ada indentation step |
| `Start_Compile (Command)` | | like `M-x compile` |
| `Define_Mode (Name, Title, Extensions, Keywords, Types, Line_Comment, Block_Comment_Start, Block_Comment_End, Backslash_Escapes := False, Case_Sensitive := True)` | | define a major mode; see below |
| `Line_Count` | Integer | |
| `Line_Text (Line)` | String | text of any line, without the newline |
| `Current_Indentation` | Integer | column of the first non-blank |
| `Indent_To (Column)` | | re-indent the current line, keeping point on its text |
| `Load (File)` | | run another script file |
| `Re_Search_Forward (Pattern, Ignore_Case := False)` | Boolean | regexp search; point moves to the end of the match |
| `Re_Search_Backward (Pattern, Ignore_Case := False)` | Boolean | point moves to the start of the match |
| `Match_Beginning (Group := 0)`, `Match_End (Group := 0)` | Integer | positions of the last regexp match or its groups |
| `Match_String (Group := 0)` | String | text of the last match or a group |
| `Set_Fill_Column (Column)` | | line width for M-q (default 70) |
| `Shell_Output (Command)` | String | run a shell command in the buffer's directory and return its output |
| `Set_Formatter (Mode, Command)` | | formatter for format_buffer; `%f` is replaced by a file holding the buffer text, and the command prints the formatted text |
| `Set_Backups (Enabled)` | | keep `file~` on the first save (default True) |
| `Set_Auto_Save (Keys, Idle_Seconds)` | | auto-save after this many keystrokes or seconds idle (defaults 300, 30) |
| `Set_Startup_Screen (Enabled)` | | show the *About* window with version and key hints at startup (default True) |
| `Set_Read_Only (Enabled)` | | make the current buffer read-only or writable (like C-x C-q) |
| `Read_Only` | Boolean | whether the current buffer is read-only |
| `Set_Line_Numbers (Enabled)` | | show line numbers in the left margin of all buffers, like M-x global_display_line_numbers_mode (default False) |
| `Set_Confirm_Exit (Enabled)` | | C-x C-c asks "Some buffers haven't been saved; leave anyway? (yes or no)" while any buffer has unsaved changes (default False) |

### Defining a mode

```ada
Define_Mode (Name       => "shell",
             Extensions => ".sh .bashrc",
             Keywords   => "if then else fi for do done case esac",
             Line_Comment => "#");
Bind_Mode_Key ("shell", "TAB", "shell_indent_line");
```

- **Extensions:** words starting with `.` match file name suffixes; other
  words match whole file names.
- **Highlighting:** keywords, types, comments (line and block, including
  multi-line block comments) and strings are coloured natively.
- **Indentation:** write it as a script command using `Line_Text`,
  `Line_Number` and `Indent_To`.
- **Example:** `share/avoe/c-mode.avoe` is a complete mode.

A procedure named `<mode>_mode_hook` (e.g. `Ada_Mode_Hook`) with
`pragma Command;` runs whenever a buffer enters that mode.

## Vectors

```ada
V : Vector := [10, 20, 30];      --  Ada 2022 style aggregates; [] is empty
V (2) := 25;                     --  1-based indexing
Append (V, 40);                  --  also Prepend (V, X) and Delete (V, Index, Count)
W := V & [50] & 60;              --  & joins vectors and elements
for X of W loop                  --  iterates over elements (or a String's characters)
   Total := Total + X;
end loop;
Message (Image (W (2 .. 3)) & Image (W'Length));
```

Vectors are values: `B := A; B (1) := 0;` leaves `A` unchanged, and
`in out` parameters change the caller's vector. Elements can be of any
type, including vectors and records. `Split`, `Join`, `Contains` and
`Sort` work on vectors.

## Records

```ada
P := (X => 1, Y => 2);
P.X := 10;
P.Label := "origin";             --  assigning adds a new field
Points := [(X => 1, Y => 1), (X => 2, Y => 4)];
Points (2).Y := 5;
if P = (X => 10, Y => 2, Label => "origin") then ...
```

Records are values too. Field names are case-insensitive, and there are no
record type declarations.

## Exceptions

```ada
Not_Found : exception;

function Find (Items : Vector; Item : String) return Positive is
begin
   for I in 1 .. Items'Length loop
      if Items (I) = Item then
         return I;
      end if;
   end loop;
   raise Not_Found with "no " & Item;
end Find;

begin
   Goto_Line (Find (Names, "main"));
exception
   when Not_Found =>
      Message (Exception_Message);
   when E : others =>             --  E holds the message
      Message (Exception_Name & ": " & Exception_Message (E));
      raise;                     --  re-raise the same exception
end;
```

- **Where handlers go:** after `exception` in a `begin ... end` block or a
  subprogram body.
- **Run-time errors:** errors such as a bad index or a type error can be
  handled as `Script_Error` (or `others`). C-g always stops the script and
  cannot be handled.
- **Unhandled exceptions:** they are reported with the place they were raised.

| Name | Returns | |
|------|---------|--|
| `Split (Source, Separator)` | Vector | without a separator: the blank-separated words |
| `Join (Items, Separator := "")` | String | |
| `Contains (Items, Item)` | Boolean | |
| `Sort (Items)` | Vector | Integers, Characters or Strings |
| `Length (Item)` | Integer | of a String or a Vector |
| `Exception_Name`, `Exception_Message (E)` | String | in a handler |

## Not (yet) supported

Record and array type declarations, packages, nested subprograms, `goto`
and loop labels.
