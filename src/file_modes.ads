--  Permission bits: reading them the way chmod(1) writes them, and showing
--  them the way ls(1) does.

package File_Modes is

   function Image (Mode : Natural) return String;
   --  "rwxr-xr-x", with s, S, t and T for the set-user, set-group and
   --  sticky bits.

   function Octal (Mode : Natural) return String;
   --  "644", or "4755" when a special bit is set.

   procedure Parse
     (Text         : String;
      Current      : Natural;
      Is_Directory : Boolean;
      Result       : out Natural;
      Ok           : out Boolean);
   --  An octal number ("644", "4755") or symbolic changes to Current, as
   --  in chmod(1): [ugoa]*[-+=][rwxXst]*, several separated by commas, for
   --  example "u+x", "go-w", "a=r", "u+rw,go-rwx".  Ok is False if Text
   --  cannot be read that way.

end File_Modes;
