separate (BBChess.Search)

   function Root_Search (Ctx        : in Context_Access;
                         Position   : in out Position_Type;
                         Depth      : in Natural;
                         Prev_Best  : in Move_Type;
                         Alpha      : in Score_Type;
                         Beta       : in Score_Type;
                         Best_Score : out Score_Type;
                         Collect    : in Boolean) return Move_Type
   is
   Current_Move_Report_Depth : constant := 8;

   procedure Report_Current_Move (Depth : in Natural;
                                  Move  : in Move_Type;
                                  Index : in Natural) is
      function Trim_Image (X : in Natural) return String is
         S : constant String := Natural'Image (X);
      begin
         return S (S'First + 1 .. S'Last);
      end Trim_Image;
   begin
      if Move = Empty_Move then
         return;
      end if;
      Locked_Put_Line
        ("info depth " & Trim_Image (Depth)
         & " currmove " & To_String (Move)
         & " currmovenumber " & Trim_Image (Index));
   end Report_Current_Move;

      Root_Moves : Move_List;
      Count      : Natural;
      --  MultiPV: the reporting thread searches every root move with a full
      --  window, so each score is exact and the K best can be reported. The
      --  historical PVS pass (window narrowing, root cutoff) is untouched
      --  when MultiPV is 1 or when this worker does not report.
      Search_All : constant Boolean := Collect and then MultiPV_Value > 1;
      A          : Score_Type := Alpha;
      B          : constant Score_Type := Beta;
      Lo         : Score_Type := Alpha;
      Hi         : Score_Type := Beta;
      Best       : Move_Type := Empty_Move;
      Best_Sc    : Score_Type := -Infinity;
      Scores     : array (Root_Moves'Range) of Score_Type :=
        (others => -Infinity);
   begin
      Generate_Legal_Moves (Position, Root_Moves, Count);

      --  "go searchmoves": keep only the requested root moves. Compared on
      --  origin/destination only, so a requested promotion square admits every
      --  promotion piece and no Flag encoding detail can make a legal move
      --  unmatched.
      if Root_Filter_N > 0 then
         declare
            Kept : Natural := 0;
         begin
            for I in 1 .. Count loop
               for J in 1 .. Root_Filter_N loop
                  if Root_Moves (I).From = Root_Filter (J).From
                    and then Root_Moves (I).To = Root_Filter (J).To
                  then
                     Kept := Kept + 1;
                     Root_Moves (Kept) := Root_Moves (I);
                     exit;
                  end if;
               end loop;
            end loop;
            Count := Kept;
         end;
      end if;

      if Count = 0 then
         Best_Score := 0;
         if Collect then
            Root_Line_N := 0;
         end if;
         return Empty_Move;
      end if;

      if Search_All then
         Lo := -Infinity;
         Hi := Infinity;
      end if;

      declare
         Ord : Order_Array;
      begin
         for J in 1 .. Count loop
            Ord (J) := Order (Ctx, Position, Root_Moves (J), Prev_Best,
                              Empty_Move, 0,
                              Is_Tactical (Position, Root_Moves (J)));
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
                     Tmp_M : constant Move_Type := Root_Moves (I);
                  begin
                     Root_Moves (I) := Root_Moves (Best_J);
                     Root_Moves (Best_J) := Tmp_M;
                  end;
                  Ord (Best_J) := Ord (I);
                  Ord (I) := Best_O;
               end if;
            end;

            declare
               Undo  : Undo_Info;
               Score : Score_Type;
            begin
               if Collect and then Report.Enabled
                 and then Depth >= Current_Move_Report_Depth
               then
                  Report_Current_Move (Depth, Root_Moves (I), I);
               end if;

               Make_Move (Position, Root_Moves (I), Undo);

               -- Publish the root move so the children at ply 1 see it as their
               -- previous move (counter-move / continuation-history lookup).
               Ctx.Move_Path (0) := Root_Moves (I);

               if I = 1 or else Search_All then
                  Score := -Negamax (Ctx, Position, Depth - 1, 1, -Hi, -Lo);
               else
                  Score := -Negamax (Ctx, Position, Depth - 1, 1, -A - 1, -A);
                  if Score > A and then Score < B then
                     Score := -Negamax (Ctx, Position, Depth - 1, 1, -B, -A);
                  end if;
               end if;

               Unmake_Move (Position, Root_Moves (I), Undo);

               Scores (I) := Score;
               if Score > Best_Sc then
                  Best_Sc := Score;
                  Best    := Root_Moves (I);
               end if;
               if not Search_All and then Score > A then
                  A := Score;
               end if;
               if A >= B then
                  exit;
               end if;
            end;
         end loop;
      end;

      if Search_All then
         --  Rank the searched root moves by their exact score (selection
         --  sort, the same pattern as the ordering pass above) so the K best
         --  can be reported.
         for I in 1 .. Count loop
            declare
               Best_J : Natural := I;
            begin
               for J in I + 1 .. Count loop
                  if Scores (J) > Scores (Best_J) then
                     Best_J := J;
                  end if;
               end loop;
               if Best_J /= I then
                  declare
                     Tmp_M : constant Move_Type := Root_Moves (I);
                     Tmp_S : constant Score_Type := Scores (I);
                  begin
                     Root_Moves (I) := Root_Moves (Best_J);
                     Scores (I)     := Scores (Best_J);
                     Root_Moves (Best_J) := Tmp_M;
                     Scores (Best_J)     := Tmp_S;
                  end;
               end if;
            end;
         end loop;
      end if;

      if Best /= Empty_Move then
         declare
            Bound : Bound_Type;
         begin
            if Search_All then
               Bound := Exact;   -- every root move was searched full width
            elsif Best_Sc >= B then
               Bound := Lower_Bound;
            elsif Best_Sc <= Alpha then
               Bound := Upper_Bound;
            else
               Bound := Exact;
            end if;
            Store (Position, Depth, Bound, Best_Sc, Best, 0);
         end;
      end if;

      if Collect then
         if Search_All then
            Root_Line_N := Natural'Min (MultiPV_Value, Count);
            for I in 1 .. Root_Line_N loop
               Root_Lines (I).Move  := Root_Moves (I);
               Root_Lines (I).Score := Scores (I);
            end loop;
         else
            Root_Line_N := 0;
         end if;
      end if;

      Best_Score := Best_Sc;
      return Best;
   end Root_Search;
