--
--  BabaChess : protocol driver (UCI + XBoard)
--
--  The engine's command loop used to live in babachess.adb, mixed with the
--  CLI and standard input. This package owns the session state and the
--  command dispatch instead; babachess.adb keeps only the thin read loop, the
--  CLI modes and the input/output itself.
--
--  Decoupling from Text_IO is done through a Line_Writer callback. The
--  protocol never touches Ada.Text_IO: it emits each output line through the
--  writer installed by the caller. In production the writer is
--  BBChess.Search.Locked_Put_Line, so protocol replies and the search task's
--  "info"/"bestmove" lines share the single console lock; in the self test it
--  is a capturing writer, which makes the dispatch testable without standard
--  input.
--
--  Why not "function Process (Line) return String": the UCI search is
--  asynchronous. A "go" starts a search in a task which emits its "bestmove"
--  (and the search its "info" lines) *after* Process has returned, and
--  "isready" must answer "readyok" while that task is running. A single return
--  value cannot carry output produced later by another task, and a bounded
--  return buffer cannot carry an unbounded multi-line handshake. The honest
--  equivalent is "feed a line, collect the emitted lines (and inspect the
--  resulting session state)"; the pure parsers in BBChess.Protocol.UCI and
--  BBChess.Protocol.XBoard are the part that is genuinely "String -> value".
--

with BBChess.Board;
with BBChess.Pieces;

package BBChess.Protocol is

   use BBChess.Board;
   use BBChess.Pieces;

   --  Where every protocol output line goes. Installed once by the caller.
   type Line_Writer is access procedure (S : in String);

   procedure Initialize (W : in Line_Writer);
   --  Reset the session to its startup state and install the output writer.
   --  Leaves the repetition history empty (Game_N = 0), exactly like the
   --  former startup: the opening book is only probed from an empty history.

   procedure Process (Line : in String);
   --  Parse and dispatch one protocol line (already without its newline).
   --  A blank line is ignored. All output is emitted through the writer.

   procedure Shutdown;
   --  Stop and terminate any running UCI search task. Called on "quit"/"exit"
   --  and when standard input reaches end of file.

   function Exit_Requested return Boolean;
   --  True once a "quit" / "exit" line has been processed.

   procedure Reset;
   --  Return the session to its startup state (keeps the installed writer).

   procedure Configure_Book (Path : in String);
   procedure Configure_Syzygy (Path : in String);
   procedure Load_Default_Book;
   --  Opening-book / tablebase configuration. Kept here so babachess.adb does
   --  not need to depend on the Polyglot / Syzygy packages directly.

   ----------------------------
   --  Observability (tests) --
   ----------------------------

   function Position_Of return Position_Type;
   function Key_Of return Bitboard;
   function Engine_Side_Of return Color_Type;
   function Is_UCI return Boolean;
   function Busy return Boolean;

end BBChess.Protocol;
