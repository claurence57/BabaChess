separate (BBChess.Protocol)

procedure Load_Default_Book is
   D    : constant String := Executable_Dir;
   Home : constant String := Home_Dir;
   Candidates : constant array (1 .. 6) of Unbounded_String :=
     (1 => To_Unbounded_String ("books/book.bin"),
      2 => To_Unbounded_String (D & "/books/book.bin"),
      3 => To_Unbounded_String (D & "/../books/book.bin"),
      4 => To_Unbounded_String (Home & "/.babachess/book.bin"),
      5 => To_Unbounded_String ("book.bin"),
      6 => To_Unbounded_String (D & "/book.bin"));
begin
   if BBChess.Polyglot.Book_Loaded then
      return;
   end if;
   --  Probing the conventional locations is best-effort: a missing
   --  candidate is the normal case, so nothing is reported here (unlike an
   --  explicit --book / setoption BookFile request, which does report).
   for C in Candidates'Range loop
      if BBChess.Polyglot.Open_Book (To_String (Candidates (C)))
           = BBChess.Polyglot.Loaded
      then
         return;
      end if;
   end loop;
end Load_Default_Book;
