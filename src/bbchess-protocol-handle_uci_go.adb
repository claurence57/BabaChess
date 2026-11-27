separate (BBChess.Protocol)

procedure Handle_UCI_Go (Par : in String) is
   use type UCI.Node_Count_Type;
   Go : constant UCI.Go_Params := UCI.Parse_Go (Par);
   --  Root move filter for this search ("go searchmoves"); empty means the
   --  full list. Installed by the search task at the start rendezvous.
   Filter_Moves : Move_List;
   Filter_N     : Natural := 0;
   --  "go mate N": a proven mate in N moves ends the search, and 2N plies
   --  is the depth cap when the GUI did not give one.
   Mate_Requested : constant Boolean :=
     Go.Has_Mate and then Go.Mate_Moves > 0;
   --  UCI_LimitStrength: a node cap derived from UCI_Elo, applied in
   --  addition to whatever the GUI sent (and only when the search is not
   --  open-ended).
   Strength_Cap : constant Node_Count_Type :=
     (if Limit_Strength and then not Go.Infinite and then not Go.Ponder
      then Nodes_For_Elo (Elo_Limit) else 0);
   Cap          : Node_Count_Type := Node_Count_Type (Go.Nodes);
   Clock_Left   : constant Duration :=
     (if Pos.Side = White then Go.Wtime else Go.Btime);
   Request      : BBChess.Search.Search_Request;
begin
   --  "go perft N": leaf count instead of a search (unofficial, but the
   --  spelling other engines accept). No bestmove is emitted.
   if Go.Has_Perft then
      Handle_UCI_Perft (Go.Perft_Depth);
      return;
   end if;

   --  "go searchmoves ...": restrict the root list for this search only.
   --  The tokens are resolved against the current position; an unknown or
   --  illegal move is reported and dropped.
   if Go.Has_Searchmoves then
      declare
         Text : constant String := To_String (Go.Searchmoves);
         N    : constant Natural := UCI.Token_Count (Text);
      begin
         for I in 1 .. N loop
            declare
               M : constant Move_Type := From_String (Pos, Token (Text, I));
            begin
               if M = Empty_Move then
                  Emit ("info string searchmoves: unknown move "
                        & Token (Text, I));
               elsif Filter_N < Filter_Moves'Length then
                  Filter_N := Filter_N + 1;
                  Filter_Moves (Filter_N) := M;
               end if;
            end;
         end loop;
      end;
   end if;

   Request.Max_Depth := Go.Depth;
   if Mate_Requested then
      Set_Mate_Limit (Go.Mate_Moves);
      if not Go.Has_Depth then
         Request.Max_Depth := 2 * Go.Mate_Moves;
      else
         Request.Max_Depth := Natural'Min (Request.Max_Depth,
                                           2 * Go.Mate_Moves);
      end if;
   else
      Set_Mate_Limit (0);
   end if;

   if Strength_Cap > 0 and then (Cap = 0 or else Cap > Strength_Cap) then
      Cap := Strength_Cap;
   end if;
   Request.Node_Cap := Cap;

   if not Go.Infinite and then not Go.Ponder
     and then Cap = 0 and then not UCI_Busy.Busy
     and then Filter_N = 0
     and then not Mate_Requested
   then
      declare
         BM : Move_Type;
      begin
         if Try_Book (BM) then
            Emit ("bestmove " & To_String (BM));
            return;
         end if;
      end;
   end if;

   if Go.Infinite or else Go.Nodes > 0
     or else (Go.Has_Depth and then Clock_Left <= 0.0
              and then not Go.Has_Movetime)
     or else (Mate_Requested and then Clock_Left <= 0.0
              and then not Go.Has_Movetime)
     or else (Strength_Cap > 0 and then Clock_Left <= 0.0
              and then not Go.Has_Movetime)
   then
      Request.Soft_Alloc := 0.0;
      Request.Hard_Alloc := 0.0;
   else
      declare
         Alloc : constant BBChess.Clocks.Allocation :=
           Time_For_Next_Move (Go, Pos.Side);
      begin
         Request.Soft_Alloc := Alloc.Soft;
         Request.Hard_Alloc := Alloc.Hard;
      end;
   end if;

   if UCI_Busy.Busy then
      Request_Stop;
   end if;

   Sync_Game_History;
   Ensure_UCI_Task;
   Active_Task.Start (Pos, Request, Go.Infinite, Go.Ponder,
                      Filter_Moves, Filter_N);
end Handle_UCI_Go;
