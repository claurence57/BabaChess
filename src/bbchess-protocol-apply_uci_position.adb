separate (BBChess.Protocol)

procedure Apply_UCI_Position (Par : in String) is
   T1 : constant String := Token (Par, 1);
   I  : Natural := 1;
   N  : constant Natural := UCI.Token_Count (Par);
   M  : Move_Type;
   U  : Undo_Info;
begin
   if T1 = "startpos" then
      Pos := Start_Position;
      I := 2;
   elsif T1 = "fen" then
      declare
         Fen  : String (1 .. 256);
         L    : Natural := 0;
         Over : Boolean := False;
      begin
         for K in 2 .. 7 loop
            declare
               Tok : constant String := Token (Par, K);
            begin
               exit when Tok'Length = 0 or else Tok = "moves";
               if L > 0 then
                  Append_Bounded (Fen, L, " ", Over);
               end if;
               Append_Bounded (Fen, L, Tok, Over);
            end;
         end loop;
         if Over then
            Emit ("info string bad FEN");
            return;
         else
            begin
               Load (Pos, Fen (1 .. L));
            exception
               when Constraint_Error =>
                  Emit ("info string bad FEN");
                  return;
            end;
         end if;
      end;
      I := 2;
   else
      return;
   end if;

   Reset_Game_History;
   while I <= N loop
      exit when Token (Par, I) = "moves";
      I := I + 1;
   end loop;
   I := I + 1;
   while I <= N loop
      M := From_String (Pos, Token (Par, I));
      if M = Empty_Move then
         Emit ("info string unknown move " & Token (Par, I));
         exit;
      else
         Make_Move (Pos, M, U);
         Record_Current_Key;
      end if;
      I := I + 1;
   end loop;
end Apply_UCI_Position;
