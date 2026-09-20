-- ***************************************************************************
--                               Avoe - Windows
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

with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

package body Windows is

   package Window_Vectors is new Ada.Containers.Vectors (Positive, Window_Access);

   List        : Window_Vectors.Vector;
   Current_Idx : Positive := 1;

   procedure Free is new Ada.Unchecked_Deallocation (Window, Window_Access);

   --  A window's point and top line are buffer markers, so they stay on
   --  the same text when the buffer is changed through another window
   procedure Attach (W : Window_Access) is
   begin
      Register_Marker (W.Buf.all, W.Point'Access);
      Register_Marker (W.Buf.all, W.Top'Access);
   end Attach;

   procedure Detach (W : Window_Access) is
   begin
      Unregister_Marker (W.Buf.all, W.Point'Access);
      Unregister_Marker (W.Buf.all, W.Top'Access);
   end Detach;

   procedure Initialize (B : Buffer_Access; Total_Rows : Positive) is
      W : constant Window_Access := new Window'
        (Buf      => B,
         Point    => B.Point,
         Top      => 0,
         Left_Col => 0,
         Height   => Positive'Max (1, Total_Rows - 1));
   begin
      List.Append (W);
      Attach (W);
      Current_Idx := 1;
   end Initialize;

   function Count return Natural is (Natural (List.Length));
   function Get (Index : Positive) return Window_Access is (List (Index));
   function Current return Window_Access is (List (Current_Idx));
   function Current_Index return Positive is (Current_Idx);
   function Current_Buffer return Buffer_Access is (Current.Buf);

   --  Commands move the buffer's point, so that is the selected window's
   --  point; other windows keep their own until they are selected
   function Point_Of (W : Window_Access) return Natural is
     (if W = Current then W.Buf.Point else W.Point);

   procedure Select_Window (Index : Positive) is
   begin
      if Index = Current_Idx then
         return;
      end if;
      Current.Point := Current.Buf.Point;
      Current_Idx := Index;
      Current.Buf.Point := Current.Point;
   end Select_Window;

   procedure Other_Window is
   begin
      Select_Window (Current_Idx mod Count + 1);
   end Other_Window;

   procedure Show_Buffer (W : Window_Access; B : Buffer_Access) is
   begin
      if W.Buf = B then
         return;
      end if;
      Detach (W);
      W.Buf := B;
      W.Point := B.Point;
      W.Top := 0;
      W.Left_Col := 0;
      Attach (W);
   end Show_Buffer;

   --  Heights do not include the mode line, hence the + 1 and - 1
   procedure Split_Current (Ok : out Boolean) is
      Cur   : constant Window_Access := Current;
      Total : constant Positive := Cur.Height + 1;
      Upper : constant Natural := (Total + 1) / 2;
   begin
      if Total < 4 then
         Ok := False;
         return;
      end if;
      declare
         W : constant Window_Access := new Window'
           (Buf      => Cur.Buf,
            Point    => Cur.Buf.Point,
            Top      => Cur.Top,
            Left_Col => Cur.Left_Col,
            Height   => Total - Upper - 1);
      begin
         Cur.Height := Upper - 1;
         List.Insert (Current_Idx + 1, W);
         Attach (W);
      end;
      Ok := True;
   end Split_Current;

   procedure Remove_At (Index : Positive) is
      W : Window_Access := List (Index);
   begin
      Detach (W);
      List.Delete (Index);
      Free (W);
      if Index < Current_Idx then
         Current_Idx := Current_Idx - 1;
      end if;
   end Remove_At;

   procedure Delete_Current (Ok : out Boolean) is
   begin
      if Count = 1 then
         Ok := False;
         return;
      end if;
      declare
         Old       : constant Positive := Current_Idx;
         Neighbour : constant Positive := (if Old > 1 then Old - 1 else 2);
      begin
         --  The window above gets the rows (the one below for the top window)
         List (Neighbour).Height := List (Neighbour).Height + List (Old).Height + 1;
         Detach (List (Old));
         declare
            W : Window_Access := List (Old);
         begin
            List.Delete (Old);
            Free (W);
         end;
         Current_Idx := (if Old > 1 then Old - 1 else 1);
         Current.Buf.Point := Current.Point;
      end;
      Ok := True;
   end Delete_Current;

   procedure Delete_Others is
      Total : Natural := 0;
   begin
      for W of List loop
         Total := Total + W.Height + 1;
      end loop;
      for I in reverse 1 .. Count loop
         if I /= Current_Idx then
            Remove_At (I);
         end if;
      end loop;
      Current.Height := Positive'Max (1, Total - 1);
   end Delete_Others;

   --  Show B in a window other than the selected one, splitting the screen
   --  if there is only one window.  Nothing happens if B is already shown.
   procedure Pop_To_Buffer (B : Buffer_Access) is
      Ok : Boolean;
   begin
      for W of List loop
         if W.Buf = B then
            return;
         end if;
      end loop;
      if Count = 1 then
         Split_Current (Ok);
         if not Ok then
            Show_Buffer (Current, B);
            return;
         end if;
      end if;
      Show_Buffer
        (List (if Current_Idx < Count then Current_Idx + 1 else Current_Idx - 1), B);
   end Pop_To_Buffer;

   procedure Replace_Buffer (Old, By : Buffer_Access) is
   begin
      for W of List loop
         if W.Buf = Old then
            Show_Buffer (W, By);
         end if;
      end loop;
   end Replace_Buffer;

   --  After a resize: remove windows until each can have two rows (text and
   --  mode line), then share the rows out evenly
   procedure Layout (Total_Rows : Positive) is
      Sum : Natural := 0;
   begin
      while Count > 1 and then Count * 2 > Total_Rows loop
         Remove_At (if Current_Idx = Count then Count - 1 else Count);
      end loop;

      for W of List loop
         Sum := Sum + W.Height + 1;
      end loop;
      if Sum = Total_Rows then
         return;
      end if;

      declare
         N    : constant Positive := Count;
         Each : constant Natural := Total_Rows / N;
         Rest : constant Natural := Total_Rows mod N;
      begin
         for I in 1 .. N loop
            List (I).Height :=
              Positive'Max (1, Each + (if I = N then Rest else 0) - 1);
         end loop;
      end;
   end Layout;

end Windows;
