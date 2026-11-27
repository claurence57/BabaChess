--
--  BabaChess : UCI command parsing (pure, no I/O)
--
--  Stateless parsers for the UCI commands whose parameters are non-trivial
--  ("go", "setoption"). They depend on nothing but the text helpers, so they
--  are directly exercised by the self test without a session or a search.
--

with Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;

package BBChess.Protocol.UCI is

   --  Protocol-level node count; converted to Search.Node_Count_Type by the
   --  caller, which keeps this pure parser independent of the search package.
   type Node_Count_Type is range 0 .. 2 ** 62;

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
         Nodes        : Node_Count_Type := 0;
         Infinite     : Boolean  := False;
         Ponder       : Boolean  := False;
         --  "searchmoves <m1> <m2> ...": the move tokens, as sent, up to the
         --  next keyword. Parsed into moves by the caller, which owns the
         --  position.
         Has_Searchmoves : Boolean := False;
         Searchmoves     : Unbounded_String := Null_Unbounded_String;
         --  "perft <n>": count the leaves at depth n instead of searching.
         Has_Perft    : Boolean  := False;
         Perft_Depth  : Natural  := 0;
         --  "mate <n>": stop the iterative deepening once a mate in n moves
         --  is proven (the caller also caps the depth at 2n plies).
         Has_Mate     : Boolean  := False;
         Mate_Moves   : Natural  := 0;
      end record;

   function Parse_Go (Parameter : in String) return Go_Params;
   --  Parse a "go" parameter list. Unknown keywords and malformed values keep
   --  the defaults (never raises). Keywords are matched case-sensitively, as
   --  the command loop did.

   --  Parameters of a "setoption" command, already lower-cased where the UCI
   --  command loop compared case-insensitively.
   type Setoption_Params is
      record
         Name     : Unbounded_String;   -- every word between "name" and "value"
         Is_Value : Boolean := False;   -- a "value" keyword was present
         Value    : Unbounded_String;   -- everything after the "value" keyword
      end record;

   function Parse_Setoption (Parameter : in String) return Setoption_Params;
   --  Split a "setoption name <name> value <value>" line. The name may contain
   --  spaces ("Move Overhead", "Clear Hash") and is lower-cased; the value
   --  keeps its original case and may contain spaces (a path).

   function Token_Count (S : in String) return Natural;
   --  Number of space separated tokens.

   function Parse_Natural (S : String; Default : Natural) return Natural;
   --  Natural'Value with the command loop's malformed-value fallback.

   function Parse_Integer (S : String; Default : Integer) return Integer;
   --  Integer'Value with the same fallback; needed by options whose value may
   --  be negative (Contempt).

end BBChess.Protocol.UCI;
