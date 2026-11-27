separate (BBChess.Search)

   procedure Poll_Time_Slow (Ctx : in Context_Access) is
   begin
      SMP_Counter.Add (Ctx.Nodes_Count - Ctx.Flushed);
      Ctx.Flushed := Ctx.Nodes_Count;
      --  Next deadline: the regular interval, but not past the node cap, so
      --  "go nodes N" stops exactly at N instead of the next interval.
      Ctx.Next_Checkpoint := Ctx.Nodes_Count + Check_Interval;
      if Ctx.Node_Limit > 0 and then Ctx.Next_Checkpoint > Ctx.Node_Limit then
         Ctx.Next_Checkpoint := Ctx.Node_Limit;
      end if;
      if Stop_Search or else Abort_Request then
         raise Search_Interrupted;
      end if;
      if Ctx.Time_Limit_Armed
        and then To_Duration (Clock - Ctx.Start_Time) >= Ctx.Time_Budget
      then
         raise Search_Interrupted;
      end if;
      if Ctx.Node_Limit > 0 and then Ctx.Nodes_Count >= Ctx.Node_Limit then
         raise Search_Interrupted;
      end if;
   end Poll_Time_Slow;
