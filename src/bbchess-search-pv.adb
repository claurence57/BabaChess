--
--  BabaChess : principal-variation extraction (body)
--

with BBChess.Search.TT;

package body BBChess.Search.PV is

   procedure Walk (Work      : in out Position_Type;
                   Pv        : out Move_List;
                   Len       : out Natural;
                   Also_Seen : in Bitboard := 0) is
      Seen      : array (1 .. Max_Length + 2) of Bitboard;
      Seen_N    : Natural := 1;
      Moves     : Move_List;
      Count     : Natural;
      Undo      : Undo_Info;
      Is_Legal  : Boolean;
   begin
      Len := 0;
      Seen (1) := Work.Key;
      if Also_Seen /= 0 then
         Seen_N := 2;
         Seen (2) := Also_Seen;
      end if;
      for Step in 1 .. Max_Length loop
         declare
            M  : Move_Type;
            Dup : Boolean := False;
         begin
            M := TT.Stored_Move (Work);
            exit when M = Empty_Move;

            Generate_Legal_Moves (Work, Moves, Count);
            Is_Legal := False;
            for I in 1 .. Count loop
               if Moves (I) = M then
                  Is_Legal := True;
                  exit;
               end if;
            end loop;
            exit when not Is_Legal;

            Make_Move (Work, M, Undo);

            -- Stop before including M if it returns to a position already
            -- seen on this PV (cycle).
            for I in 1 .. Seen_N loop
               if Seen (I) = Work.Key then
                  Dup := True;
                  exit;
               end if;
            end loop;
            exit when Dup;

            Len := Len + 1;
            Pv (Len) := M;
            Seen_N := Seen_N + 1;
            Seen (Seen_N) := Work.Key;
         end;
      end loop;
   end Walk;

   procedure Extract (Root : in Position_Type;
                      Pv   : out Move_List;
                      Len  : out Natural) is
      Work : Position_Type := Root;
   begin
      Walk (Work, Pv, Len);
   end Extract;

   procedure Extract_Line (Root  : in Position_Type;
                           First : in Move_Type;
                           Pv    : out Move_List;
                           Len   : out Natural) is
      Work : Position_Type := Root;
      Undo : Undo_Info;
      Rest : Move_List;
      N    : Natural;
   begin
      Len := 1;
      Pv (1) := First;
      Make_Move (Work, First, Undo);
      Walk (Work, Rest, N, Also_Seen => Root.Key);
      for I in 1 .. N loop
         exit when Len = Pv'Length;
         Len := Len + 1;
         Pv (Len) := Rest (I);
      end loop;
   end Extract_Line;

end BBChess.Search.PV;
