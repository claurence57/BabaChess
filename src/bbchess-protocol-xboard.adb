--
--  BabaChess : XBoard command parsing (body)
--

with BBChess.Text;
use BBChess.Text;

package body BBChess.Protocol.XBoard is

   ----------------
   -- Parse_Number --
   ----------------

   function Parse_Number (Text : in String; Default : Duration) return Duration is
   begin
      if Text'Length = 0 then
         return Default;
      end if;
      return Duration'Value (Text);
   exception
      when Constraint_Error => return Default;
   end Parse_Number;

   -------------------------
   -- Parse_Centiseconds --
   -------------------------

   function Parse_Centiseconds (Text : in String) return Duration is
      V : Duration;
   begin
      if Text'Length = 0 then
         return 0.0;
      end if;
      V := Duration'Value (Text);
      return V / 100.0;
   exception
      when Constraint_Error => return 0.0;
   end Parse_Centiseconds;

   -----------------
   -- Parse_Level --
   -----------------

   function Parse_Level (Parameter : in String) return Level_Params is
      Mps_Token  : constant String := Token (Parameter, 1);
      Base_Token : constant String := Token (Parameter, 2);
      Inc_Token  : constant String := Token (Parameter, 3);
      Result     : Level_Params;
   begin
      -- Increment (seconds). A missing or malformed field means none.
      Result.Increment_Seconds := Parse_Number (Inc_Token, 0.0);

      -- Moves per session: 0 means "no session limit".
      begin
         Result.Moves_Per_Session := Natural'Value (Mps_Token);
      exception
         when Constraint_Error =>
            Result.Moves_Per_Session := 0;
      end;

      -- A plain "level M base" uses whole minutes as the base. An "MM:SS"
      -- base (used by cutechess) means the real clock will be provided later
      -- by the "time" command, so Base_Seconds is left at 0.0 and the caller
      -- must not overwrite its clock.
      for I in Base_Token'Range loop
         if Base_Token (I) = ':' then
            Result.Base_Has_Colon := True;
            exit;
         end if;
      end loop;
      if not Result.Base_Has_Colon then
         begin
            Result.Base_Seconds :=
              Duration (Natural'Value (Base_Token) * 60);
         exception
            when Constraint_Error =>
               Result.Base_Seconds := 0.0;
         end;
      end if;

      return Result;
   end Parse_Level;

end BBChess.Protocol.XBoard;
