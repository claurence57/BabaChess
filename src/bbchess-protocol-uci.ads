--
--  BabaChess : UCI command parsing (pure, no I/O)
--
--  Stateless parsers for the UCI commands whose parameters are non-trivial
--  ("go", "setoption"). They depend on nothing but the text helpers and the
--  search node-count type, so they are directly exercised by the self test
--  without a session, a search or standard input.
--

with BBChess.Search;

with Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;

package BBChess.Protocol.UCI is

   --  Parameters of a "go" command. Both clocks are returned: the caller picks
   --  the one matching the side to move (wtime/winc for White, btime/binc for
   --  Black), exactly as the former inline command loop did.
   type Go_Params is
      record
         Wtime        : Duration := 0.0;
         Btime        : Duration := 0.0;
         Winc         : Duration := 0.0;
         Binc         : Duration := 0.0;
         Movestogo    : Natural  := 0;
         Movetime     : Duration := 1.0;
         Has_Movetime : Boolean  := False;
         Depth        : Natural  := 64;
         Has_Depth    : Boolean  := False;
         Nodes        : BBChess.Search.Node_Count_Type := 0;
         Infinite     : Boolean  := False;
      end record;

   function Parse_Go (Parameter : in String) return Go_Params;
   --  Parse a "go" parameter list. Unknown keywords and malformed values keep
   --  the defaults (never raises). Keywords are matched case-sensitively, as
   --  the command loop did.

   --  Parameters of a "setoption" command, already lower-cased where the UCI
   --  command loop compared case-insensitively.
   type Setoption_Params is
      record
         Name     : Unbounded_String;
         Token3   : Unbounded_String;   -- third token, lower-cased
         Is_Value : Boolean;            -- third token is exactly "value"
         Value    : Unbounded_String;   -- everything from the fourth token
      end record;

   function Parse_Setoption (Parameter : in String) return Setoption_Params;
   --  Split a "setoption name <name> value <value>" line. The name and the
   --  third token are lower-cased (UCI is case-insensitive); the value keeps
   --  its original case and may contain spaces (a path).

   function Token_Count (S : in String) return Natural;
   --  Number of space separated tokens.

   function Parse_Natural (S : String; Default : Natural) return Natural;
   --  Natural'Value with the command loop's malformed-value fallback.

end BBChess.Protocol.UCI;
