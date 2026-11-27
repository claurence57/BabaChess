separate (BBChess.Search)

   function Quiescence (Ctx        : in Context_Access;
                        Position   : in out Position_Type;
                        Alpha, Beta : in Score_Type;
                        Ply        : in Natural;
                        QDepth     : in Natural) return Score_Type
   is
      A        : Score_Type := Alpha;
      B        : constant Score_Type := Beta;
      In_Check : constant Boolean := King_In_Check (Position, Position.Side);
      Stand    : Score_Type := 0;
      Moves    : Move_List;
      Count    : Natural;
      Limit    : Natural;
      -- Quiescence TT: probe and store only when enabled; a slot already
      -- holding a full-width (depth >= 1) result is never overwritten.
      Use_TT   : constant Boolean := Search_Params (S_Qs_TT) /= 0;
      May_Store : Boolean := Use_TT;

      function Finish (Score : in Score_Type) return Score_Type is
      begin
         if May_Store then
            Store (Position, 0,
                   (if Score >= B then Lower_Bound
                    elsif Score <= Alpha then Upper_Bound
                    else Exact),
                   Score, Empty_Move, Ply);
         end if;
         return Score;
      end Finish;
   begin
      Poll_Time (Ctx);

      --  Deepest ply reached (UCI "seldepth"). One comparison per node; the
      --  value is only ever reported, never used by the search.
      if Ply > Ctx.Sel_Depth then
         Ctx.Sel_Depth := Natural'Min (Max_Ply, Ply);
      end if;

      -- Depth bound: stop expanding once the quiescence cap is reached.
      if QDepth >= Max_Q_Depth then
         if In_Check then
            -- In check at the cap: the evasions cannot be searched (that would
            -- defeat the bound), so only mate is detected. If evasions exist,
            -- the real value is unknown.
            Generate_Legal_Moves (Position, Moves, Count);
            if Count = 0 then
               return -(Mate_Score - Ply);
            end if;
            --  A in the negative mate band is the real hazard: the parent
            --  negates this return, so handing it back would be read as a
            --  proven mate. Return a bounded static value instead (unsafe as
            --  a normal eval because the node is in check, but the bound only
            --  matters when A is already that extreme). Outside the band A is
            --  the correct fail-low bound.
            if A <= -Mate_Threshold then
               return Score_Type'Min (B, Evaluate (Position));
            end if;
            return A;
         else
            -- Not in check: the alpha-updated stand-pat score is the safe
            -- truncation (exactly the score the unbounded search would use
            -- as its floor before trying more captures).
            Stand := Evaluate (Position);
            if Stand >= B then
               return Stand;
            end if;
            if Stand > A then
               A := Stand;
            end if;
            return Mate_Clamp (A);
         end if;
      end if;

      if Use_TT then
         declare
            R : constant Probe_Result :=
              Probe (Position, Ply, A, B, Min_Depth => 0);
         begin
            if R.Hit then
               --  A hit with a real depth replaces the entry on the way out;
               --  an empty marker (depth -1) must not.
               if R.Stored_Depth >= 1 then
                  May_Store := False;
               end if;
               if R.Cut then
                  return R.Score;
               end if;
            end if;
         end;
      end if;

      -- Stand pat is only legal when not in check: a side that is in check
      -- must play an evasion, so the static evaluation cannot be returned.
      if not In_Check then
         Stand := Evaluate (Position);
         if Stand >= B then
            return Stand;
         end if;
         if Stand > A then
            A := Stand;
         end if;
      end if;

      if In_Check then
         --  Every evasion must be tried; otherwise only captures and
         --  promotions are generated.
         Generate_Legal_Moves (Position, Moves, Count);
      else
         -- Only captures / promotions are searched in a quiet position, so
         -- there is no need to generate the (numerous) quiet moves. In_Check
         -- is already known to be False here, so the generator is told to skip
         -- the check-detection lookup it would otherwise repeat.
         Generate_Legal_Tactical_Moves (Position, Moves, Count,
                                        Not_In_Check => True);
      end if;

      if Count = 0 and then In_Check then
         return Finish (-(Mate_Score - Ply));
      end if;

      -- Move the tactical moves (captures / promotions) to the front, then
      -- order them by MVV so the most promising captures are tried first.
      -- The victim value is computed once per tactical move (and carried
      -- through the selection swaps) instead of once per comparison. In a
      -- quiet position the generator already yields only tactical moves, so
      -- the partition (and its per-move Is_Tactical test) is skipped; the
      -- selection sort below then sees the same T = Count prefix.
      declare
         T : Natural := 0;
         Vic : Order_Array;
      begin
         if In_Check then
            for I in 1 .. Count loop
               if Is_Tactical (Position, Moves (I)) then
                  T := T + 1;
                  Vic (T) := Ordering_Value (Captured_Kind (Position, Moves (I)));
                  declare
                     Tmp : constant Move_Type := Moves (T);
                  begin
                     Moves (T) := Moves (I);
                     Moves (I) := Tmp;
                  end;
               end if;
            end loop;
         else
            T := Count;
            for I in 1 .. Count loop
               Vic (I) := Ordering_Value (Captured_Kind (Position, Moves (I)));
            end loop;
         end if;

         for I in 1 .. T loop
            declare
               Best_J : Natural := I;
               Best_V : Score_Type := Vic (I);
            begin
               for J in I + 1 .. T loop
                  if Vic (J) > Best_V then
                     Best_V := Vic (J);
                     Best_J := J;
                  end if;
               end loop;
               if Best_J /= I then
                  declare
                     Tmp : constant Move_Type := Moves (I);
                     Tmp_V : constant Score_Type := Vic (I);
                  begin
                     Moves (I) := Moves (Best_J);
                     Moves (Best_J) := Tmp;
                     Vic (I) := Vic (Best_J);
                     Vic (Best_J) := Tmp_V;
                  end;
               end if;
            end;
         end loop;

         -- When in check every legal move is an evasion and must be tried
         -- (a quiet king move is a legal answer to a check), not just the
         -- tactical subset searched in quiet positions.
         if In_Check then
            Limit := Count;
         else
            Limit := T;
         end if;

         for I in 1 .. Limit loop
            -- A capture that the static exchange evaluation scores as losing
            -- cannot improve on the stand-pat score, so it is not searched
            -- (promotions and evasions out of check are always kept). For a
            -- non-check node the loop only walks the tactical prefix, whose
            -- victim value is already in Vic.
            if (not In_Check)
              and then Moves (I).Flag /= Promotion
              and then (Stand + Vic (I) + Delta_Margin <= A
                        or else Static_Exchange_Value (Position, Moves (I)) < 0)
            then
               null;
            else
               declare
                  Undo  : Undo_Info;
                  Score : Score_Type;
               begin
                  Make_Move (Position, Moves (I), Undo);
                  Score := -Quiescence (Ctx, Position, -B, -A, Ply + 1,
                                        QDepth + 1);
                  Unmake_Move (Position, Moves (I), Undo);

                  if Score >= B then
                     return Finish (Score);
                  end if;
                  if Score > A then
                     A := Score;
                  end if;
               end;
            end if;
         end loop;

      end;

      return Finish (A);
   end Quiescence;
