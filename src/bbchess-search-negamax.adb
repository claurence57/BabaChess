separate (BBChess.Search)

   function Negamax (Ctx        : in Context_Access;
                     Position   : in out Position_Type;
                     Depth_In, Ply : in Natural;
                     Alpha, Beta : in Score_Type) return Score_Type
   is
      -- Remaining depth; lowered by the internal iterative reduction.
      Depth       : Natural := Depth_In;
      A           : Score_Type := Alpha;
      B           : Score_Type := Beta;
      --  A full-window node lies on the principal variation; a zero-window
      --  (scout) node does not. Derived from the incoming window, captured
      --  here before the mate-distance clamp below narrows A / B.
      Is_PV       : constant Boolean := (Beta - Alpha) > 1;
      Moves       : Move_List;
      Count       : Natural;
      Hash_Move   : Move_Type := Empty_Move;
      In_Check    : Boolean := False;
      Best_Move_Here : Move_Type := Empty_Move;
      Best_Score  : Score_Type := -Infinity;
      Child_Depth : Natural := 0;
      Eval_Now    : Score_Type := 0;
      Have_Eval   : Boolean := False;
      -- Move made on the previous ply (the move that led to this node); the
      -- counter-move and continuation-history orderings key on it.
      Prev        : Move_Type := Empty_Move;
   begin
      Poll_Time (Ctx);

      --  Deepest ply reached (UCI "seldepth"), same as in Quiescence.
      if Ply > Ctx.Sel_Depth then
         Ctx.Sel_Depth := Natural'Min (Max_Ply, Ply);
      end if;

      -- Recover the previous move from this thread's per-ply move path. The
      -- value is a by-value copy and every parent writes its own slot just
      -- before recursing, so no stale pointer survives an Unmake.
      if Ply >= 1 and then Ply - 1 <= Max_Ply then
         Prev := Ctx.Move_Path (Ply - 1);
      end if;

      -- Terminal draws: the fifty-move rule and dead positions are scored
      -- as draws before anything else, including the quiescence call and the
      -- transposition probe (the Zobrist key does not include the halfmove
      -- clock, so a TT hit must not shadow the draw). Checkmate outranks the
      -- fifty-move claim: at exactly 100 halfmoves the side to move can be
      -- mated, so the draw is only taken when the position is not mate.
      if Position.Halfmove >= 100
        or else Insufficient_Material (Position)
      then
         if King_In_Check (Position, Position.Side) then
            declare
               Moves : Move_List;
               Count : Natural;
            begin
               Generate_Legal_Moves (Position, Moves, Count);
               if Count = 0 then
                  return -(Mate_Score - Ply);
               end if;
            end;
         end if;
         return Draw_Value (Ply);
      end if;

      if Depth = 0 then
         return Quiescence (Ctx, Position, A, B, Ply, 0);
      end if;

      -- Prefetch the transposition-table bucket now, so its cache miss is
      -- resolved by the time the probe below reads it (the prologue and the
      -- repetition/syzygy/mate-distance checks in between hide the latency).
      Prefetch (Position);

      -- Record the current node on the search path (for the repetition
      -- detection of its descendants) and claim a draw on a repetition
      -- before trusting the transposition table.
      if Ply <= Max_Ply then
         Ctx.Search_Path (Ply) := Position.Key;
      end if;
      if Is_Repetition (Ctx, Position, Ply) then
         return Draw_Value (Ply);
      end if;

      -- Syzygy tablebase: an exact WDL result, when the loaded tables cover
      -- this material. Positions with castling rights are not probed (the
      -- probe returns -1 for them). With Syzygy50MoveRule on, only a
      -- zero-clock position is probed: rule50 cannot matter there, so the
      -- verdict is exact and the clock-free TT key stays sound. With the rule
      -- off, the clock is ignored by construction (rule50 = 0 in the probe),
      -- which is precisely what lets any clock be probed.
      if BBChess.Syzygy.Enabled
        and then (Position.Halfmove = 0
                  or else not BBChess.Syzygy.Fifty_Move_Rule)
        and then Popcount (Position.All_Occ) <= BBChess.Syzygy.Largest
      then
         declare
            W : constant Integer := BBChess.Syzygy.Probe_WDL (Position);
         begin
            if W >= 0 then
               TB_Hits.Add;
            end if;
            case W is
               when 4 =>                     -- TB_WIN
                  return BBChess.Syzygy.TB_Win - Ply;
               when 0 =>                     -- TB_LOSS
                  return -(BBChess.Syzygy.TB_Win - Ply);
               when 1 | 2 | 3 =>             -- draw / blessed / cursed
                  --  A tablebase verdict is objective: Contempt is deliberately
                  --  not applied here (a theoretical draw stays a draw).
                  return 0;
               when others =>
                  null;
            end case;
         end;
      end if;

      -- Mate-distance pruning: no node can score better than a mate found
      -- at the current ply, nor worse than being mated right now.
      declare
         M_Alpha : constant Score_Type := -Mate_Score + Ply;
         M_Beta  : constant Score_Type := Mate_Score - Ply - 1;
      begin
         if A < M_Alpha then
            A := M_Alpha;
         end if;
         if B > M_Beta then
            B := M_Beta;
         end if;
         if A >= B then
            return A;
         end if;
      end;

      -- Transposition table probe (two-way bucket). Data and Key_Xor are read
      -- as atomic words and the slot is accepted only when they verify against
      -- Position.Key (self-verifying entry, no ABA window under Lazy SMP).
      declare
         R : constant Probe_Result :=
           Probe (Position, Ply, A, B, Min_Depth => Integer (Depth));
      begin
         if R.Hit then
            if R.Cut then
               return R.Score;
            end if;
            Hash_Move := R.Move;
         end if;
      end;

      Generate_Legal_Moves (Position, Moves, Count, In_Check);

      if Count = 0 then
         if In_Check then
            return -(Mate_Score - Ply);
         else
            return Draw_Value (Ply);
         end if;
      end if;

      -- Internal iterative reduction: without a hash move the ordering is
      -- poor, so the node is searched one ply shallower.
      if Search_Params (S_Iir_Depth) > 0
        and then Hash_Move = Empty_Move
        and then Depth >= Natural'Max (2, Natural (Search_Params (S_Iir_Depth)))
      then
         Depth := Depth - 1;
      end if;

      -- Static evaluation for the pruning decisions (only needed out of
      -- check, at low depth, or at any depth when the null move or the
      -- reverse futility pruning consult it).
      if not In_Check
        and then (Depth <= 3
                  or else Search_Params (S_Nmp_Eval) /= 0
                  or else Depth <= Natural (Search_Params (S_Rfp_Depth)))
      then
         Eval_Now := Evaluate (Position);
         Have_Eval := True;
      end if;

      -- Razoring: when the static evaluation is far below alpha, verify with
      -- a quiescence search and return it if it does not reach alpha.
      if Can_Razor (Depth, In_Check, Have_Eval, Eval_Now, Alpha) then
         declare
            Q : constant Score_Type := Quiescence (Ctx, Position, A, B, Ply, 0);
         begin
            if Q < Alpha then
               return Q;
            end if;
         end;
      end if;

      -- Check extension: evasions are forced, so an in-check node is
      -- searched one ply deeper than a quiet one. Bounded by Ply so that a
      -- long checking sequence cannot explode the search.
      if In_Check and then Depth >= Natural (Search_Params (S_Check_Ext_Min_Depth))
        and then Ply <= Max_Ply
          - Search_Params (S_Check_Ext_Ply_Guard)
      then
         Child_Depth := Depth;
      else
         Child_Depth := Depth - 1;
      end if;

      -- Reverse futility pruning.
      if Can_Reverse_Futility (Depth, In_Check, Have_Eval, Eval_Now, B) then
         return Eval_Now;
      end if;

      -- Null-move pruning (skip in pawn-only endgames / when in check, and
      -- never twice in a row). The null block clears this node's Move_Path
      -- slot, so a node reached right after a null move reads Prev =
      -- Empty_Move and is thereby barred from nulling again.
      if Can_Null_Move (Depth, In_Check, Prev, Position)
        and then (Search_Params (S_Nmp_Eval) = 0
                  or else (Have_Eval and then Eval_Now >= B))
      then
         declare
            -- Only Side, En_Passant and Key are touched here (the recursive
            -- call restores the board through Unmake), so saving just those
            -- three fields avoids copying the whole Position.
            Saved_Side : constant Color_Type := Position.Side;
            Saved_Ep   : constant Integer := Position.En_Passant;
            Saved_Key  : constant Bitboard := Position.Key;
            -- Standard adaptive null-move reduction: deeper nodes get a
            -- larger reduction (R = 3 + Depth / 4, integer division).
            N_Reduction : constant Natural :=
              Search_Params (S_Null_Red_Base)
              + Depth / Natural (Search_Params (S_Null_Red_Div));
            N_Depth     : Natural;
            N_Score    : Score_Type;
         begin
            -- Guard the child depth so it stays a valid Natural: at shallow
            -- depth the adaptive formula can reach or exceed Depth - 1.
            if N_Reduction >= Depth - 1 then
               N_Depth := 0;
            else
               N_Depth := Depth - 1 - N_Reduction;
            end if;
            if Position.En_Passant /= Ep_None then
               Position.Key :=
                 Position.Key xor Hash.Ep_Key (Position.En_Passant mod 8);
            end if;
            Position.En_Passant := Ep_None;
            Position.Side := Opposite (Position.Side);
            Position.Key := Position.Key xor Hash.Side_Key;

            -- A null move has no real predecessor: clear this node's move
            -- slot so the null child does not pick up a stale move (from an
            -- unrelated subtree at the same ply) as its previous move.
            if Ply <= Max_Ply then
               Ctx.Move_Path (Ply) := Empty_Move;
            end if;

            N_Score := -Negamax (Ctx, Position, N_Depth,
                                 Ply + 1, -B, -B + 1);

            Position.Side := Saved_Side;
            Position.En_Passant := Saved_Ep;
            Position.Key := Saved_Key;
            if N_Score >= B then
               return N_Score;
            end if;
         end;
      end if;

      -- ProbCut: a capture worth at least the margin, searched with beta
      -- raised by the margin at a reduced depth, already proves the node
      -- fails high when the probe beats the raised bound. Restricted to
      -- non-PV nodes: the principal variation must be exact, not a probe.
      if Search_Params (S_Probcut) /= 0
        and then not In_Check
        and then not Is_PV
        and then Depth >= Natural (Search_Params (S_Probcut_Depth))
      then
         declare
            Margin : constant Score_Type := Search_Params (S_Probcut_Margin);
            -- The raised bound must stay out of the mate band: a returned
            -- score at or above Mate_Threshold would be read as a proven mate.
            Bound  : constant Score_Type := B + Margin;
            Red    : constant Natural := Natural (Search_Params (S_Probcut_Red));
            Enemy  : constant Bitboard :=
              Color_Board (Position, Opposite (Position.Side));
            -- Never recurse with a negative depth (Red may exceed Depth).
            Probe_Depth : constant Natural :=
              (if Red >= Depth then 1 else Depth - Red);
            Probed : Natural := 0;
         begin
            if Margin > 0 and then Bound < Mate_Threshold then
               for I in 1 .. Count loop
                  exit when Probed >= Natural (Search_Params (S_Probcut_Max));
                  if (Moves (I).Flag in En_Passant | Promotion
                      or else (Enemy and Bit (Moves (I).To)) /= 0)
                    and then Static_Exchange_Value (Position, Moves (I)) >= Margin
                  then
                     Probed := Probed + 1;
                     declare
                        Undo  : Undo_Info;
                        Score : Score_Type;
                     begin
                        Make_Move (Position, Moves (I), Undo);
                        if Ply <= Max_Ply then
                           Ctx.Move_Path (Ply) := Moves (I);
                        end if;
                        Score := -Negamax (Ctx, Position, Probe_Depth, Ply + 1,
                                            -Bound, -Bound + 1);
                        Unmake_Move (Position, Moves (I), Undo);
                        if Score >= Bound then
                           return Score;
                        end if;
                     end;
                  end if;
               end loop;
            end if;
         end;
      end if;

      -- Move ordering, then PVS over the children.
      declare
         Ord : Order_Array;
         -- Occupancy of the side not to move, loop-invariant during the
         -- ordering pass; the per-move tactical test is then a single bit
         -- test against it (same predicate as Is_Tactical).
         Enemy_Occ : constant Bitboard :=
           Color_Board (Position, Opposite (Position.Side));
      begin
         for J in 1 .. Count loop
            Ord (J) := Order (Ctx, Position, Moves (J), Hash_Move, Prev, Ply,
                              (Moves (J).Flag in En_Passant | Promotion
                               or else (Enemy_Occ and Bit (Moves (J).To)) /= 0));
         end loop;

         for I in 1 .. Count loop
            declare
               Best_J : Natural := I;
               Best_O : Score_Type := Ord (I);
            begin
               for J in I + 1 .. Count loop
                  if Ord (J) > Best_O then
                     Best_O := Ord (J);
                     Best_J := J;
                  end if;
               end loop;
               if Best_J /= I then
                  declare
                     Tmp_M : constant Move_Type := Moves (I);
                  begin
                     Moves (I) := Moves (Best_J);
                     Moves (Best_J) := Tmp_M;
                  end;
                  Ord (Best_J) := Ord (I);
                  Ord (I) := Best_O;
               end if;
            end;

            declare
               Undo    : Undo_Info;
               Score   : Score_Type;
               -- Same predicate the ordering pass uses; recomputed here so the
               -- tactical flag is not carried through the sort in a third
               -- array (only Moves and Ord need to be permuted).
               Tactical : constant Boolean :=
                 Moves (I).Flag in En_Passant | Promotion
                 or else (Enemy_Occ and Bit (Moves (I).To)) /= 0;
               Reduction : Natural := 0;
               Move_Depth : constant Natural := Child_Depth;
            begin
                -- Late move pruning: at low depth the late quiet moves are
                -- simply skipped (they are ordered last and almost never
                -- improve on the already searched moves).
                if Can_Late_Move_Prune (Depth, In_Check, Tactical,
                                        Best_Score, I)
                then
                   goto Next_Move;
                end if;

                -- Futility pruning: a quiet move whose static evaluation plus
                -- a depth-scaled margin cannot reach alpha is not searched.
                if Can_Futility_Prune (Depth, In_Check, Tactical, Have_Eval,
                                       Best_Score, Eval_Now, Alpha)
                then
                   goto Next_Move;
                end if;

                -- Late move reduction for late quiet moves (log formula).
                if not Tactical and then Depth >= 3 and then I >= 4
                  and then not In_Check
                then
                   Reduction :=
                     LMR_Table (Natural'Min (Depth, LMR_Max_Depth),
                                Natural'Min (I, LMR_Max_Move));
                   -- History-guided adjustment: a quiet move with a good
                   -- history score is reduced less, a bad one more. Only the
                   -- history band of the ordering score is used (killers and
                   -- the counter-move score far above it).
                   if Search_Params (S_Lmr_Hist) > 0
                     and then Ord (I) < 500_000
                   then
                      declare
                         Adj : constant Integer := Integer'Max
                           (-2, Integer'Min
                              (2, Ord (I) / Search_Params (S_Lmr_Hist)));
                      begin
                         Reduction := Natural
                           (Integer'Max (0, Integer (Reduction) - Adj));
                      end;
                   end if;
                   --  A PV node lies on the principal variation: reduce it
                   --  one ply less; a zero-window (cut) node in turn reduces
                   --  one ply more (its result only has to prove a cutoff).
                   if Is_PV then
                      if Reduction > 0 then
                         Reduction := Reduction - 1;
                      end if;
                   else
                      Reduction := Reduction + 1;
                   end if;
                   --  Killers are known-good quiet moves: never reduce them.
                   if Ply <= Max_Ply
                     and then (Moves (I) = Ctx.Killers (1, Ply)
                               or else Moves (I) = Ctx.Killers (2, Ply))
                   then
                      Reduction := 0;
                   end if;
                   if Reduction >= Child_Depth then
                      Reduction := Child_Depth - 1;
                   end if;
                end if;

               Make_Move (Position, Moves (I), Undo);

               --  A move that gives check leaves the opponent a forced,
               --  constrained reply: reduce it one ply less. Tested after the
               --  move is made, so Position.Side is now the opponent.
               if Reduction > 0
                 and then King_In_Check (Position, Position.Side)
               then
                  Reduction := Reduction - 1;
               end if;

               -- Record the move for the child's previous-move lookup. The
               -- parent rewrites its own slot on every iteration and the child
               -- copies it by value at node entry, so the value is always the
               -- move actually on the board above it.
               if Ply <= Max_Ply then
                  Ctx.Move_Path (Ply) := Moves (I);
               end if;

               if I = 1 then
                  Score := -Negamax (Ctx, Position, Move_Depth, Ply + 1, -B, -A);
               else
                  Score := -Negamax (Ctx, Position, Move_Depth - Reduction,
                                     Ply + 1, -A - 1, -A);
                  if Reduction > 0 and then Score > A then
                     -- Verify a reduced fail-high at full depth.
                     Score := -Negamax (Ctx, Position, Move_Depth, Ply + 1,
                                        -A - 1, -A);
                  end if;
                  if Score > A and then Score < B then
                     Score := -Negamax (Ctx, Position, Move_Depth, Ply + 1,
                                        -B, -A);
                  end if;
               end if;

               Unmake_Move (Position, Moves (I), Undo);

               -- Penalize a quiet move that failed to raise the window, so
               -- the history (and continuation history) heuristics learn to
               -- avoid it.
               if not Tactical and then Ply <= Max_Ply
                 and then Score <= Alpha
               then
                  Bump_History (Ctx, Position.Side, Moves (I).From,
                                Moves (I).To, -History_Bonus (Depth));
                  if Prev /= Empty_Move then
                     Bump_Cont_History (Ctx, Prev, Moves (I),
                                        -History_Bonus (Depth));
                  end if;
               end if;

               if Score > Best_Score then
                  Best_Score := Score;
                  Best_Move_Here := Moves (I);
               end if;
               if Score >= B then
                  if not Tactical and then Ply <= Max_Ply then
                     if Ctx.Killers (1, Ply) /= Moves (I) then
                        Ctx.Killers (2, Ply) := Ctx.Killers (1, Ply);
                        Ctx.Killers (1, Ply) := Moves (I);
                     end if;
                     Bump_History (Ctx, Position.Side, Moves (I).From,
                                   Moves (I).To, History_Bonus (Depth));
                     -- Learn the refutation of the opponent's previous move:
                     -- Counter is keyed by the mover of that previous move.
                     if Prev /= Empty_Move then
                        Ctx.Counter (Opposite (Position.Side), Prev.From,
                                     Prev.To) := Moves (I);
                        Bump_Cont_History (Ctx, Prev, Moves (I),
                                           History_Bonus (Depth));
                     end if;
                  end if;
                  Store (Position, Depth, Lower_Bound, Score,
                         Best_Move_Here, Ply);
                  return Score;
               end if;
               if Score > A then
                  A := Score;
               end if;
            end;
            <<Next_Move>>
            null;
         end loop;
      end;

      declare
         Bound : Bound_Type;
      begin
         if A <= Alpha then
            Bound := Upper_Bound;
         elsif A >= B then
            Bound := Lower_Bound;
         else
            Bound := Exact;
         end if;
         Store (Position, Depth, Bound, A, Best_Move_Here, Ply);
      end;

      return A;
   end Negamax;
