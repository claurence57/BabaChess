--
--  BabaChess : minimal test harness (body)
--

with Ada.Text_IO;

package body BBChess.Test_Harness is

   Pass_Count : Natural := 0;
   Fail_Count : Natural := 0;

   procedure Reset is
   begin
      Pass_Count := 0;
      Fail_Count := 0;
   end Reset;

   procedure Check (Condition : in Boolean; Message : in String) is
   begin
      if Condition then
         Pass_Count := Pass_Count + 1;
      else
         Fail_Count := Fail_Count + 1;
         Ada.Text_IO.Put_Line ("FAILED: " & Message);
      end if;
   end Check;

   function Passed return Natural is
   begin
      return Pass_Count;
   end Passed;

   function Failed return Natural is
   begin
      return Fail_Count;
   end Failed;

end BBChess.Test_Harness;
