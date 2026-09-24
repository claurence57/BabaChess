--
--  BabaChess : UCI command parsing (body)
--

with Ada.Characters.Handling;

with BBChess.Text;
use BBChess.Text;

package body BBChess.Protocol.UCI is

   use Ada.Characters.Handling;

   function Token_Count (S : in String) return Natural is
      I : Natural := S'First;
      N : Natural := 0;
   begin
      while I <= S'Last loop
         while I <= S'Last and then S (I) = ' ' loop
            I := I + 1;
         end loop;
         exit when I > S'Last;
         N := N + 1;
         while I <= S'Last and then S (I) /= ' ' loop
            I := I + 1;
         end loop;
      end loop;
      return N;
   end Token_Count;

   function Parse_Duration (S : String; Default : Duration) return Duration is
   begin
      if S'Length = 0 then
         return Default;
      end if;
      return Duration'Value (S);
   exception
      when Constraint_Error => return Default;
   end Parse_Duration;

   function Parse_Natural (S : String; Default : Natural) return Natural is
   begin
      if S'Length = 0 then
         return Default;
      end if;
      return Natural'Value (S);
   exception
      when Constraint_Error => return Default;
   end Parse_Natural;

   function Parse_Node_Count (S : String; Default : BBChess.Search.Node_Count_Type)
     return BBChess.Search.Node_Count_Type is
   begin
      if S'Length = 0 then
         return Default;
      end if;
      return BBChess.Search.Node_Count_Type'Value (S);
   exception
      when Constraint_Error => return Default;
   end Parse_Node_Count;

   ---------------
   -- Parse_Go --
   ---------------

   function Parse_Go (Parameter : in String) return Go_Params is
      N : constant Natural := Token_Count (Parameter);
      I : Natural := 1;
      Result : Go_Params;
   begin
      while I <= N loop
         declare
            Name : constant String := Token (Parameter, I);
            Next : constant String :=
              (if I < N then Token (Parameter, I + 1) else "");
         begin
            if Name = "wtime" then
               Result.Wtime := Parse_Duration (Next, 0.0) / 1000.0;
            elsif Name = "btime" then
               Result.Btime := Parse_Duration (Next, 0.0) / 1000.0;
            elsif Name = "winc" then
               Result.Winc := Parse_Duration (Next, 0.0) / 1000.0;
            elsif Name = "binc" then
               Result.Binc := Parse_Duration (Next, 0.0) / 1000.0;
            elsif Name = "movestogo" then
               Result.Movestogo := Parse_Natural (Next, 0);
            elsif Name = "movetime" then
               Result.Has_Movetime := True;
               Result.Movetime := Parse_Duration (Next, 1.0) / 1000.0;
            elsif Name = "depth" then
               Result.Depth := Parse_Natural (Next, 64);
               Result.Has_Depth := True;
            elsif Name = "nodes" then
               Result.Nodes := Parse_Node_Count (Next, 0);
            elsif Name = "infinite" then
               Result.Infinite := True;
            end if;
         end;
         I := I + 1;
      end loop;
      return Result;
   end Parse_Go;

   ----------------------
   -- Parse_Setoption --
   ----------------------

   function Parse_Setoption (Parameter : in String) return Setoption_Params is
      Result : Setoption_Params;
   begin
      Result.Name     := To_Unbounded_String (To_Lower (Token (Parameter, 2)));
      Result.Token3   := To_Unbounded_String (To_Lower (Token (Parameter, 3)));
      Result.Is_Value := Result.Token3 = To_Unbounded_String ("value");
      Result.Value    := To_Unbounded_String (Token_Rest (Parameter, 4));
      return Result;
   end Parse_Setoption;

end BBChess.Protocol.UCI;
