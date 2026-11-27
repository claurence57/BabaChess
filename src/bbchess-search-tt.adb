--
--  BabaChess : transposition table (body)
--
--  Entry encoding (64 bits):
--      Move 23 | Score 16 | Depth 8 | Bound 2 | Age 15
--  Depth 255 marks an empty slot; the stored score fits 16 bits because mate
--  scores are normalised to the root and stay within +/-30_200.
--
--  MEMORY MODEL (x86-64 only): the lock-free table relies on the x86-64 TSO
--  (Total Store Order) model. There are exactly three pragma Atomic in the
--  tree (Data, Key_Xor, Num_Threads), no pragma Volatile and no explicit
--  memory barrier anywhere; correctness rests on two TSO guarantees:
--    * a naturally aligned 64-bit load/store is a single atomic access (no
--      tearing), which is what makes the self-verifying key work;
--    * each thread's stores are observed in program order by every other
--      thread, so a reader that sees a slot's Data also sees the Key_Xor
--      written before it (and vice versa), and the xor verification rejects
--      any pair that was not written together.
--  This is NOT portable to a weak model (ARM/AArch64, POWER): there the
--  compiler and CPU may reorder the two independent stores, and a reader
--  could observe a Data/Key_Xor pair from different writes that still
--  verifies. Porting to such a target would require release/acquire
--  semantics or an explicit barrier. Do not change this scheme without
--  revisiting the assumption; see DEVELOPMENT.md section 61.
--

with Ada.Unchecked_Deallocation;
with Ada.Text_IO;

with System;

package body BBChess.Search.TT is

   --  Transposition-table entry: a single 64-bit Data word plus a
   --  self-verifying Key_Xor = Key xor Data. Both are Atomic, so on x86-64
   --  every read/write is one 64-bit access. A reader accepts a slot only
   --  when (Key_Xor xor Data) = Position.Key; a torn read (Data from one
   --  store, Key_Xor from another) cannot satisfy that, so a foreign payload
   --  can never be used. This closes the ABA window of the previous
   --  "key written last" scheme, where a slot replaced between the key test
   --  and the copy could pair the new key with a stale payload.
   type TT_Entry is
      record
         Data    : Bitboard := 0 with Atomic;
         Key_Xor : Bitboard := 0 with Atomic;
      end record;

   Data_Score_Shift : constant := 23;
   Data_Depth_Shift : constant := 39;
   Data_Bound_Shift : constant := 47;
   Data_Age_Shift   : constant := 49;
   Empty_Depth      : constant := 255;

   TT_Entry_Bytes : constant := 16;

   type TT_Array is array (Natural range <>) of TT_Entry;
   type TT_Array_Access is access all TT_Array;

   --  Cache-line aligned so a 16-byte bucket (two entries) never straddles a
   --  64-byte line; the default alignment is only a coincidence.
   for TT_Array'Alignment use 64;

   procedure Free_TT is new Ada.Unchecked_Deallocation (TT_Array, TT_Array_Access);

   Transposition_Table : TT_Array_Access := null;
   TT_Size : Natural := 0;                                -- entries
   TT_Mask : Bitboard := 0;                               -- TT_Size - 1

   -- Current search generation, used to age entries: an entry left over from
   -- a previous search is replaced before a fresh one.
   TT_Generation : Natural := 0;

  Replacement : Replacement_Policy;

  procedure Set_Replacement_Policy (Policy : in Replacement_Policy) is
  begin
     Replacement := Policy;
  end Set_Replacement_Policy;

   function Gen_Mod return Natural is (TT_Generation mod 32_768);
   pragma Inline (Gen_Mod);

   --  Keep an unsearched fail-low bound out of the mate band: under negamax
   --  the parent reads -S, so a bound already in the band would be mistaken
   --  for a proven mate. Inert at the default parameters (the bound stays far
   --  from the band), so the tree is unchanged.
   function Mate_Clamp (S : in Score_Type) return Score_Type is
     (Score_Type'Max (-(Mate_Threshold - 1),
                      Score_Type'Min (S, Mate_Threshold - 1)));

   -- Two entries form a bucket (even index and the next one).
   function TT_Bucket (Position : in Position_Type) return Natural is
     (Natural (Position.Key and (TT_Mask - 1)));
   pragma Inline (TT_Bucket);

   --  Data field encoding / decoding.
   function Encode_Score (S : Score_Type) return Bitboard is
      V : constant Integer :=
        Integer'Max (-32_768, Integer'Min (32_767, Integer (S)));
   begin
      return Bitboard (V mod 65_536);
   end Encode_Score;
   pragma Inline (Encode_Score);

   function Make_Data (Move : Packed_Move; Score : Score_Type;
                       Depth : Natural; Bound : Bound_Type;
                       Age : Natural) return Bitboard is
     (Bitboard (Move mod (2 ** 23))
      or Encode_Score (Score) * (2 ** Data_Score_Shift)
      or Bitboard (Natural'Min (Depth, Empty_Depth - 1))
           * (2 ** Data_Depth_Shift)
      or Bitboard (Bound_Type'Pos (Bound)) * (2 ** Data_Bound_Shift)
      or Bitboard (Age mod 32_768) * (2 ** Data_Age_Shift));
   pragma Inline (Make_Data);

   function Data_Move (D : Bitboard) return Packed_Move is
     (Packed_Move (D mod (2 ** 23)));

   function Data_Score (D : Bitboard) return Score_Type is
      U : constant Natural :=
        Natural ((D / (2 ** Data_Score_Shift)) mod 65_536);
   begin
      if U >= 32_768 then
         return Score_Type (U - 65_536);
      end if;
      return Score_Type (U);
   end Data_Score;

   function Data_Depth (D : Bitboard) return Natural is
     (Natural ((D / (2 ** Data_Depth_Shift)) mod 256));

   --  Signed depth: -1 for an empty slot (the old TT_Depth_Type marker),
   --  otherwise 0 .. 254. Keeps the replacement / acceptance policy
   --  identical to the previous 16-bit depth field.
   function Data_Depth_Signed (D : Bitboard) return Integer is
      X : constant Natural := Data_Depth (D);
   begin
      if X = Empty_Depth then
         return -1;
      end if;
      return Integer (X);
   end Data_Depth_Signed;

   function Data_Bound (D : Bitboard) return Bound_Type is
      P : constant Natural :=
        Natural ((D / (2 ** Data_Bound_Shift)) mod 4);
   begin
      if P <= 2 then
         return Bound_Type'Val (P);
      end if;
      return Exact;
   end Data_Bound;

   function Data_Age (D : Bitboard) return Natural is
     (Natural ((D / (2 ** Data_Age_Shift)) mod 32_768));

   Data_Empty : constant Bitboard :=
     Bitboard (Empty_Depth) * (2 ** Data_Depth_Shift);

   --  A slot is usable only when the two atomic words are consistent with
   --  the searched key.
   function Key_Match (E : TT_Entry; Key : Bitboard) return Boolean is
     ((E.Key_Xor xor E.Data) = Key);
   pragma Inline (Key_Match);

   --  Read a TT slot for reporting (PV extraction), returning its Data when
   --  it verifies against Key. A concurrent Lazy-SMP store writes the two
   --  64-bit words separately, so a 16-byte copy can tear and be rejected;
   --  the PV is never a search input, so one retry makes that false negative
   --  rare.
   function TT_Slot_Read (Bk : Natural; Key : Bitboard;
                          Data : out Bitboard) return Boolean is
      E : TT_Entry;
   begin
      E := Transposition_Table (Bk);
      if not Key_Match (E, Key) then
         E := Transposition_Table (Bk);
      end if;
      if Key_Match (E, Key) then
         Data := E.Data;
         return True;
      end if;
      return False;
   end TT_Slot_Read;

   --  Software prefetch of a TT slot, issued at node entry so the probe's
   --  cache miss overlaps with the prologue (draw / repetition / mate
   --  checks). A pure hint: it has no architectural effect and cannot change
   --  the search.
   procedure C_Prefetch (P : in System.Address)
     with Import, Convention => Intrinsic, External_Name => "__builtin_prefetch";
   pragma Inline (C_Prefetch);

   function Adjust_Score (S : Score_Type; Ply : Natural) return Score_Type is
   begin
      if S >= Mate_Threshold then
         return S - Ply;
      elsif S <= -Mate_Threshold then
         return S + Ply;
      end if;
      return S;
   end Adjust_Score;
   pragma Inline (Adjust_Score);

   ----------------
   --  Allocation --
   ----------------

   procedure Clear is
   begin
      -- Cleared entry by entry: an aggregate assignment of the whole table
      -- would be built on the (limited) main-thread stack.
      if TT_Size = 0 then
         return;   --  nothing allocated yet (elaboration order)
      end if;
      for I in 0 .. TT_Size - 1 loop
         Transposition_Table (I).Data    := Data_Empty;
         -- Empty marker: stored key 0, so Key_Xor = 0 xor Data_Empty = 0.
         -- A probe then matches only if Position.Key = Data_Empty, which a
         -- real Zobrist key never is.
         Transposition_Table (I).Key_Xor := 0;
      end loop;
   end Clear;

   procedure New_Search is
   begin
      TT_Generation := TT_Generation + 1;
   end New_Search;

   --  Round N down to the nearest power of two (N >= 1).
   function Power_Of_Two_At_Most (N : in Natural) return Natural is
      P : Natural := 1;
   begin
      while P <= N / 2 loop
         P := P * 2;
      end loop;
      return P;
   end Power_Of_Two_At_Most;

   --  (Re)allocate the table for a request in MiB. The new table is built
   --  before the old one is released, so a failed allocation leaves the
   --  engine with a working (smaller) table rather than none: on
   --  Storage_Error the request is halved and retried down to Min_MB.
   procedure Set_Size (MB : in Natural) is
      Want    : Natural := Natural'Max (Min_MB, Natural'Min (Max_MB, MB));
      Entries : Natural;
      Fresh   : TT_Array_Access;
   begin
      loop
         Entries := Power_Of_Two_At_Most
                      (Want * (1024 * 1024) / TT_Entry_Bytes);
         begin
            Fresh := new TT_Array (0 .. Entries - 1);
            exit;
         exception
            when Storage_Error =>
               if Want <= Min_MB then
                  raise;
               end if;
               Want := Natural'Max (Min_MB, Want / 2);
         end;
      end loop;

      if Transposition_Table /= null then
         Free_TT (Transposition_Table);
      end if;
      Transposition_Table := Fresh;
      TT_Size := Entries;
      TT_Mask := Bitboard (Entries - 1);
      TT_Generation := 0;
      Clear;
   end Set_Size;

   function Size_MB return Natural is
      -- Run-time sized table: TT_Size entries of TT_Entry bytes.
      Bytes : constant Natural := TT_Size * (TT_Entry'Size / 8);
   begin
      return Bytes / (1024 * 1024);
   end Size_MB;

   --  Per-mille occupancy of the table by entries written during the current
   --  search generation (the "hashfull" figure UCI reports). Sampled every
   --  Step slots: a full scan would cost more than the information is worth.
   function Hashfull return Natural is
      Samples : constant := 1_000;
      Step    : constant Natural := Natural'Max (1, TT_Size / Samples);
      Age     : constant Natural := Gen_Mod;
      Used    : Natural := 0;
      Seen    : Natural := 0;
   begin
      if Transposition_Table = null then
         return 0;
      end if;
      declare
         I : Natural := 0;
      begin
         while I < TT_Size loop
            declare
               D : constant Bitboard := Transposition_Table (I).Data;
            begin
               if Data_Depth_Signed (D) >= 0 and then Data_Age (D) = Age then
                  Used := Used + 1;
               end if;
            end;
            Seen := Seen + 1;
            I := I + Step;
         end loop;
      end;
      return Used * 1_000 / Natural'Max (1, Seen);
   end Hashfull;

   ---------------
   --  Prefetch --
   ---------------

   procedure Prefetch (Position : in Position_Type) is
   begin
      C_Prefetch (Transposition_Table (TT_Bucket (Position))'Address);
   end Prefetch;

   ------------
   --  Probe --
   ------------

   function Probe (Position  : in Position_Type;
                   Ply       : in Natural;
                   Alpha     : in Score_Type;
                   Beta      : in Score_Type;
                   Min_Depth : in Integer) return Probe_Result
   is
      Bk : constant Natural := TT_Bucket (Position);
      E  : TT_Entry := Transposition_Table (Bk);
      R  : Probe_Result;
   begin
      if not Key_Match (E, Position.Key) then
         E := Transposition_Table (Bk + 1);
         if not Key_Match (E, Position.Key) then
            return R;      --  Hit stays False
         end if;
      end if;

      declare
         D : constant Bitboard := E.Data;
         S : constant Score_Type := Adjust_Score (Data_Score (D), Ply);
      begin
         R.Hit := True;
         R.Score := S;
         R.Stored_Depth := Data_Depth_Signed (D);
         R.Move := Unpack_Move (Data_Move (D));
         if R.Stored_Depth >= Min_Depth then
            case Data_Bound (D) is
               when Exact =>
                  R.Cut := True;
               when Lower_Bound =>
                  R.Cut := S >= Beta;
               when Upper_Bound =>
                  R.Cut := S <= Alpha;
            end case;
         end if;
      end;
      return R;
   end Probe;

   -------------
   --  Store  --
   -------------

   --  Keep-score of a stored entry, used by the scored replacement policy
   --  (S_Tt_Replace = 1). Higher means more worth keeping:
   --    * depth in plies dominates;
   --    * an exact-bound (PV) entry is worth S_Tt_Pv_Bonus extra plies, so a
   --      slightly shallower PV line survives a deeper bound-only entry;
   --    * an entry written by an older search generation loses
   --      S_Tt_Age_Penalty, which (well above Max_Ply) makes it the first
   --      thing dropped, whatever its depth.
   --  Empty slots score far below every real entry.
   function Repl_Score (D : Bitboard) return Integer is
   begin
      if Data_Depth_Signed (D) < 0 then
         return -1_000_000;
      end if;
      return Data_Depth_Signed (D)
        + (if Data_Bound (D) = Exact
           then Replacement.PV_Bonus else 0)
        + (if Data_Age (D) = Gen_Mod
           then 0 else -Replacement.Age_Penalty);
   end Repl_Score;
   pragma Inline (Repl_Score);

   -- Store a node. Mate scores are normalized by the distance to the root
   -- so they stay comparable across different depths. The two-way bucket
   -- keeps the deeper of the two entries and replaces stale ones first.
   -- Under Lazy SMP the table is written without locking: the payload and
   -- the self-verifying key are published as two Atomic 64-bit words, and a
   -- reader accepts the slot only when Key_Xor xor Data equals its key, so a
   -- racing store can never present a foreign payload as valid.
   procedure Store (Position : in Position_Type;
                    Depth     : in Natural;
                    Bound     : in Bound_Type;
                    Score     : in Score_Type;
                    Move      : in Move_Type;
                    Ply       : in Natural)
   is
      B      : constant Natural := TT_Bucket (Position);
      Packed : constant Packed_Move := Pack_Move (Move);
      Saved  : Score_Type := Score;
      Slot   : Natural;
      Repl   : Boolean;
      D_B, D_1 : Bitboard;
      E_B, E_1 : TT_Entry;
      Match_B, Match_1 : Boolean;
      Gen    : constant Natural := Gen_Mod;
   begin
      if Saved >= Mate_Threshold then
         Saved := Saved + Ply;
      elsif Saved <= -Mate_Threshold then
         Saved := Saved - Ply;
      end if;

      -- Read each slot once; reuse both the payload and the key check.
      E_B := Transposition_Table (B);
      E_1 := Transposition_Table (B + 1);
      D_B := E_B.Data;
      D_1 := E_1.Data;
      Match_B := Key_Match (E_B, Position.Key);
      Match_1 := Key_Match (E_1, Position.Key);

      -- Prefer a matching key, then an empty slot, then a stale entry, then
      -- the shallower of the two.
      if not Replacement.Scored then
         if Match_B then
            Slot := B;
         elsif Match_1 then
            Slot := B + 1;
         elsif Data_Depth_Signed (D_B) < 0 then
            Slot := B;
         elsif Data_Depth_Signed (D_1) < 0 then
            Slot := B + 1;
         elsif Data_Age (D_B) /= Gen
           and then Data_Age (D_1) = Gen
         then
            Slot := B;
         elsif Data_Age (D_1) /= Gen
           and then Data_Age (D_B) = Gen
         then
            Slot := B + 1;
         elsif Data_Depth_Signed (D_1) < Data_Depth_Signed (D_B) then
            Slot := B + 1;
         else
            Slot := B;
         end if;
      else
         --  Scored policy: the same key is refreshed, otherwise the less
         --  valuable of the two entries (Repl_Score) makes way. Empty slots
         --  score far below everything, so they are taken first.
         if Match_B then
            Slot := B;
         elsif Match_1 then
            Slot := B + 1;
         elsif Repl_Score (D_1) < Repl_Score (D_B) then
            Slot := B + 1;
         else
            Slot := B;
         end if;
      end if;

      declare
         Old_D : constant Bitboard := (if Slot = B then D_B else D_1);
         Match : constant Boolean := (if Slot = B then Match_B else Match_1);
      begin
         if not Replacement.Scored then
            Repl := Data_Depth_Signed (Old_D) < 0
              or else Match
              or else Depth >= Natural'Max (0, Data_Depth_Signed (Old_D))
              or else Data_Age (Old_D) /= Gen;
         else
            --  The new entry is from the current generation, so it carries no
            --  age penalty; it is written when it is worth at least as much as
            --  what occupies the slot (a tie refreshes the entry, as in the
            --  historical policy).
            Repl := Match
              or else Integer (Depth)
                        + (if Bound = Exact
                           then Replacement.PV_Bonus else 0)
                      >= Repl_Score (Old_D);
         end if;
      end;

      if Repl then
         declare
            New_Data : constant Bitboard :=
              Make_Data (Packed, Saved, Depth, Bound, Gen);
         begin
            -- Data first (with the old Key_Xor still in place the slot does
            -- not verify), then Key_Xor = Key xor Data. A concurrent reader
            -- sees either a non-verifying intermediate state or the final
            -- consistent pair; it can never accept a foreign payload.
            Transposition_Table (Slot).Data := New_Data;
            Transposition_Table (Slot).Key_Xor := Position.Key xor New_Data;
         end;
      end if;
   end Store;

   -------------------
   --  Stored move  --
   -------------------

   function Stored_Move (Position : in Position_Type) return Move_Type is
      Bk : constant Natural := TT_Bucket (Position);
      D  : Bitboard;
   begin
      if TT_Slot_Read (Bk, Position.Key, D)
        or else TT_Slot_Read (Bk + 1, Position.Key, D)
      then
         return Unpack_Move (Data_Move (D));
      end if;
      return Empty_Move;
   end Stored_Move;

   ---------------
   --  Self test --
   ---------------

   function Self_Test return Boolean is
      D : Bitboard;
      R : Boolean := True;
   begin
      -- Score round-trip, including the signed extremes and mate scores.
      for S in Score_Type range -30_200 .. 30_200 loop
         D := Make_Data (0, S, 0, Exact, 0);
         if Data_Score (D) /= S then
            R := False;
            exit;
         end if;
      end loop;

      -- Depth 0 and the maximum depth, plus the empty marker.
      D := Make_Data (123, 0, 0, Exact, 0);
      R := R and then Data_Depth_Signed (D) = 0;
      D := Make_Data (123, 0, Empty_Depth - 1, Lower_Bound, 7);
      R := R and then Data_Depth_Signed (D) = Empty_Depth - 1;
      R := R and then Data_Bound (D) = Lower_Bound;
      R := R and then Data_Age (D) = 7;
      R := R and then Data_Move (D) = 123;
      R := R and then Data_Depth_Signed (Data_Empty) = -1;

      -- Self-verifying key: matching key accepted, wrong key rejected.
      D := Make_Data (0, 42, 3, Exact, 1);
      declare
         E : constant TT_Entry := (Data => D, Key_Xor => 16#1234# xor D);
      begin
         R := R and then Key_Match (E, 16#1234#);
         R := R and then not Key_Match (E, 16#9999#);
      end;

      if not R then
         Ada.Text_IO.Put_Line ("TT data self-test: FAILED");
      end if;
      return R;
   end Self_Test;

end BBChess.Search.TT;
