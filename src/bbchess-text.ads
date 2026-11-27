--
--  AdaChess-BB : bounded text handling (spec)
--
--  Small helpers shared by the command loop and its self tests. The release
--  build is compiled with -gnatp (run-time checks off), so every copy here is
--  bounded explicitly and can never write past the destination buffer. They
--  also avoid relying on Constraint_Error, which would be unchecked away.
--

with Interfaces;

package BBChess.Text is

   --  Single source of truth for the engine version. It feeds the UCI
   --  "id name" line, the "--version" command-line option and the startup
   --  banner, so a release only changes this line.
   BabaChess_Version : constant String := "1.6.0";

   function Hex_Image (Value : in Interfaces.Unsigned_64) return String;
   --  Sixteen lower-case hexadecimal digits, zero padded, no prefix: the
   --  usual rendering of a 64-bit Zobrist key.

   procedure Append_Bounded (Dest      : in out String;
                             Last      : in out Natural;
                             Source    : in String;
                             Truncated : out Boolean);
   -- Append Source to Dest, whose valid prefix is Dest (Dest'First .. Last)
   -- (Last is the number of characters already there). Characters that do not
   -- fit are dropped and Truncated is set. Never raises.

   procedure Split_Command (Line      : in String;
                            Command   : out String;
                            Cmd_Last  : out Natural;
                            Parameter : out String;
                            Par_Last  : out Natural);
   -- Split an already trimmed protocol line into its first word (lower-cased)
   -- and the rest of the line, copied with an explicit bound into Command and
   -- Parameter. A word longer than Command is truncated instead of
   -- overwriting neighbouring state (the release build has checks disabled).

   function Token (Source : in String; N : in Positive) return String;
   -- N-th space separated token of Source ("" when there is none).

   function Token_Rest (Source : in String; N : in Positive) return String;
   -- Everything from the N-th token to the end of Source, leading blanks
   -- trimmed ("" when there is no N-th token). Used for option values that
   -- may contain spaces (a book or tablebase path).

   function Trim_Both (S : in String) return String;
   -- Trim spaces/tabs at both ends.

   function Thread_Count (Argument : in String; Default : in Natural)
     return Natural;
   -- Thread count parsed from a single command-line argument: "-TN" or
   -- "--thread=N". Returns Default (0 means "no match") when Argument is
   -- neither form or the value is malformed. The two-argument form
   -- ("--threads N") is resolved by the caller.

end BBChess.Text;
