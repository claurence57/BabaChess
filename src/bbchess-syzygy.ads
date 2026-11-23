--
--  AdaChess-BB : Syzygy endgame tablebases (via the Fathom C library)
--
--  Thin Ada binding over Fathom (vendored in src/fathom). WDL probing is
--  used in the search; the probe is only valid without castling rights and
--  with a zero halfmove clock (Fathom rejects such positions).
--

with Interfaces.C;

with BBChess.Board;
use BBChess.Board;

with BBChess.Moves;
use BBChess.Moves;

package BBChess.Syzygy is

   -- Scores returned by the search for a tablebase win/loss (below mate,
   -- above any normal evaluation), adjusted by the ply for distance.
   TB_Win  : constant Integer := 20_000;

   -- Fathom WDL values.
   TB_Result_Failed       : constant Interfaces.C.unsigned := 16#FFFF_FFFF#;

   procedure Init (Path : in String; Ok : out Boolean);
   -- Initialise the tablebases from a directory (or list of directories)
   -- separated by the platform path separator. Ok is False when no usable
   -- tablebase is found (Largest is then 0).

   procedure Free;
   -- Release the tablebases.

   function Largest return Natural;
   -- Largest number of pieces available in the loaded tablebases (0 = none).

   function Enabled return Boolean;
   -- True when at least one tablebase is loaded.
   pragma Inline (Enabled);

   procedure Set_Fifty_Move_Rule (On : in Boolean);
   --  UCI "Syzygy50MoveRule" (default True). True honours the fifty-move
   --  rule: the search only trusts a WDL verdict with a zero halfmove clock
   --  (where rule50 cannot matter) and the DTZ root probe receives the real
   --  halfmove count, so a cursed win is classified as a draw. False ignores
   --  the rule: both probes pass rule50 = 0 and the search may probe positions
   --  whose clock is non-zero, counting a cursed win as a win -- the analysis
   --  / correspondence reading, where the rule does not apply. Must not be
   --  changed while a search is running.

   function Fifty_Move_Rule return Boolean;
   pragma Inline (Fifty_Move_Rule);

   function Probe_WDL (Position : in Position_Type) return Integer;
   -- Fathom WDL value (0..4) from the side to move's point of view, or -1 when
   -- the probe fails (no tablebase, or castling rights). The halfmove clock is
   -- passed as rule50 when Syzygy50MoveRule is on, and ignored (rule50 = 0)
   -- when it is off; the caller decides which clocks it is willing to trust
   -- (the search probes a non-zero clock only with the rule ignored).

   function Has_DTZ return Boolean;
   -- True when the loaded tablebases include DTZ data (distance to zero),
   -- required by the root probe. False with WDL-only tables.
   pragma Inline (Has_DTZ);

   function Probe_Root_Move
     (Position : in Position_Type; Move : out Move_Type;
      Wdl : out Integer) return Boolean;
   -- DTZ root probe (Fathom tb_probe_root): on success fills Move with a move
   -- that preserves the WDL value while minimising the distance to zero, and
   -- sets Wdl to that value (0..4, from the side to move's point of view), then
   -- returns True. Returns False when the probe fails (no DTZ tables, castling
   -- rights, > Largest pieces, or an unavailable material). The halfmove clock
   -- is passed as rule50 when Syzygy50MoveRule is on (a cursed/blessed result
   -- then accounts for the 50-move context) and ignored when it is off. NOT
   -- thread-safe: call once at the search root only.

end BBChess.Syzygy;
