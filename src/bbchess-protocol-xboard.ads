--
--  BabaChess : XBoard command parsing (pure, no I/O)
--
--  Stateless helpers for the XBoard/Winboard commands that carry parameters
--  ("level", "time", "st", "sd"). Kept out of the session so the self test can
--  check the parsing (and the centisecond / minute conversions) directly.
--

package BBChess.Protocol.XBoard is

   type Level_Params is
      record
         Moves_Per_Session : Natural  := 0;
         Base_Seconds      : Duration := 0.0;
         Increment_Seconds : Duration := 0.0;
         Base_Has_Colon    : Boolean  := False;  -- "MM:SS": clock comes later
      end record;

   function Parse_Level (Parameter : in String) return Level_Params;
   --  "level <MPS> <base> <inc>". A malformed numeric field falls back to 0
   --  (never raises). An "MM:SS" base sets Base_Has_Colon: the real clock is
   --  then expected from a later "time" command.

   function Parse_Number (Text : in String; Default : Duration) return Duration;
   --  Duration'Value with the command loop's malformed-value fallback.

   function Parse_Centiseconds (Text : in String) return Duration;
   --  XBoard "time" is in centiseconds: seconds = value / 100. Malformed input
   --  yields 0.0.

end BBChess.Protocol.XBoard;
