separate (BBChess.Protocol)

procedure Load_Default_Syzygy is
   D    : constant String := Executable_Dir;
   Home : constant String := Home_Dir;

   function Has_Tablebase (Dir : in String) return Boolean is
      use Ada.Directories;
      Search : Search_Type;
      E      : Directory_Entry_Type;
      Found  : Boolean := False;
   begin
      if Dir'Length = 0 or else not Exists (Dir)
        or else Kind (Dir) /= Directory
      then
         return False;
      end if;
      Start_Search (Search, Dir, "*.rtbw");
      while More_Entries (Search) loop
         Get_Next_Entry (Search, E);
         if Kind (E) = Ordinary_File then
            Found := True;
            exit;
         end if;
      end loop;
      End_Search (Search);
      return Found;
   end Has_Tablebase;

   Candidates : constant array (1 .. 4) of Unbounded_String :=
     (1 => To_Unbounded_String ("syzygy"),
      2 => To_Unbounded_String (D & "/syzygy"),
      3 => To_Unbounded_String (Home & "/.babachess/syzygy"),
      4 => To_Unbounded_String (D & "/../syzygy"));
begin
   --  An explicit setoption SyzygyPath (or --syzygy) wins: Fathom keeps
   --  the paths given at its last Init, so probing here would clobber it.
   if BBChess.Syzygy.Enabled then
      return;
   end if;
   for C in Candidates'Range loop
      declare
         Path : constant String := To_String (Candidates (C));
         Ok   : Boolean;
      begin
         if Has_Tablebase (Path) then
            BBChess.Syzygy.Init (Path, Ok);
            if Ok then
               return;
            end if;
         end if;
      end;
   end loop;
end Load_Default_Syzygy;
