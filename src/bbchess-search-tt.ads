--
--  BabaChess : transposition table
--
--  The table itself: a run-time sized array of two-word buckets whose entry
--  is self-verifying (a 64-bit Data word plus Key_Xor = Key xor Data, both
--  Atomic). It owns the allocation, the ageing generation, the replacement
--  policy and the entry encoding; the search only probes and stores.
--
--  Split out of BBChess.Search so the table can be read -- and its encoding
--  tested -- on its own. The memory-model reasoning (x86-64 TSO, no ABA
--  window) is in the body, next to the code that relies on it.
--

--  Score_Type / Mate_Score come from BBChess.Eval; the position, move and
--  piece types are already use-visible through the parent's context.

with BBChess.Eval;
use BBChess.Eval;

package BBChess.Search.TT is

   type Bound_Type is (Exact, Lower_Bound, Upper_Bound);

   --  Scores at or above this magnitude are mate scores (a mate in N plies
   --  scores Mate_Score - N). Shared with the search, which uses it to tell
   --  a mate from a material score and to keep a fail-low bound out of the
   --  band.
   Mate_Threshold : constant Score_Type := Mate_Score - 1000;

   --  Size limits of the run-time allocation, in MiB (UCI "Hash").
   Default_MB : constant := 64;

   Min_MB     : constant := 1;
   Max_MB     : constant := 1_024;

   function Mate_Clamp (S : in Score_Type) return Score_Type;
   pragma Inline (Mate_Clamp);
   --  Keep a score out of the mate band (a fail-low bound already in the
   --  band would be mistaken for a proven mate by the parent).

   procedure Set_Size (MB : in Natural);
   --  (Re)allocate the table. The entry count is rounded down to a power of
   --  two (the two-entry bucket then stays inside the table).

   procedure Clear;
   --  Empty every slot (keeps the allocation).

   procedure New_Search;
   --  Start a new search: the generation is incremented, so entries left by
   --  the previous search age out and are replaced first.

   type Replacement_Policy is record
      Scored       : Boolean := True;
      PV_Bonus     : Integer := 4;
      Age_Penalty  : Integer := 24;
   end record;

   procedure Set_Replacement_Policy (Policy : in Replacement_Policy);
   --  Snapshot the policy before a search. The caller changes search parameters
   --  only while no search is running, so Store reads no Search state.

   function Hashfull return Natural;
   --  Per-mille of slots written during the current generation (sampled).

   function Size_MB return Natural;
   --  Effective allocation, in MiB (after rounding down).

   procedure Prefetch (Position : in Position_Type);
   pragma Inline (Prefetch);
   --  Software prefetch of the bucket, issued at node entry.

   type Probe_Result is record
      Hit          : Boolean    := False;
      --  A slot verified against Position.Key.
      Cut          : Boolean    := False;
      --  That entry is deep enough (Stored_Depth >= Min_Depth) and its bound
      --  settles the node against (Alpha, Beta).
      Score        : Score_Type := 0;
      --  Mate-normalised score, from the point of view of the side to move
      --  at Ply (valid when Hit).
      Stored_Depth : Integer    := -1;
      --  Signed depth of the entry: -1 for an empty marker, else 0 .. 254.
      Move         : Move_Type  := Empty_Move;
      --  Move stored with the entry (Empty_Move when there is none).
   end record;

   function Probe (Position  : in Position_Type;
                   Ply       : in Natural;
                   Alpha     : in Score_Type;
                   Beta      : in Score_Type;
                   Min_Depth : in Integer) return Probe_Result;
   pragma Inline (Probe);
   --  Read the two-entry bucket once and decide. Min_Depth is the shallowest
   --  entry that may cut: the remaining depth in the main search, 0 in
   --  quiescence (where any scored entry is usable).

   procedure Store (Position : in Position_Type;
                    Depth    : in Natural;
                    Bound    : in Bound_Type;
                    Score    : in Score_Type;
                    Move     : in Move_Type;
                    Ply      : in Natural);
   --  Write a node under the replacement policy in force (see S_Tt_Replace).
   --  Mate scores are stored relative to the root, so they stay comparable
   --  across depths.

   function Stored_Move (Position : in Position_Type) return Move_Type;
   --  Move of the entry that verifies against Position.Key, Empty_Move when
   --  there is none. For the PV walk only: one retry on a torn read (a
   --  concurrent Lazy-SMP store may publish the two words separately).

   function Self_Test return Boolean;
   --  Round-trip the entry encoding (scores, depth, bound, age, move) and
   --  the self-verifying key. Prints the failure when it does not hold.

end BBChess.Search.TT;
