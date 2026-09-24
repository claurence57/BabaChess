--
--  AdaChess-BB : Polyglot opening book support
--
--  Computes Polyglot Zobrist keys and probes standard Polyglot .bin opening
--  books (16-byte entries, big-endian, sorted by key).
--

with BBChess.Board;
use BBChess.Board;

with BBChess.Moves;
use BBChess.Moves;

package BBChess.Polyglot is

   function Polyglot_Key (Position : in Position_Type) return Bitboard;
   -- Polyglot Zobrist hash of Position, compatible with .bin book entries.

   type Load_Status is
     (Loaded,          -- a valid book is now in memory
      File_Not_Found,  -- the file cannot be opened
      Empty_File,      -- zero-length file
      Truncated,       -- shorter than one 16-byte entry
      Bad_Size,        -- size is not a multiple of the 16-byte entry size
      Read_Error);     -- a short read / I/O error while loading

   function Open_Book (File_Name : in String) return Load_Status;
   -- Load a Polyglot .bin book into memory. Any previously loaded book is
   -- released first. Returns Loaded on success, or the precise reason the file
   -- was rejected. The book parser never raises and never lets a malformed
   -- file yield a crash or an illegal move: only well-formed 16-byte entries
   -- are stored, and Probe re-validates every move against the position.

   function Status_Message (Status : in Load_Status; File_Name : in String)
     return String;
   -- Human-readable one-line explanation of a non-Loaded status, for the
   -- caller to report (keeps this package free of any I/O).

   procedure Close_Book;
   -- Release the in-memory book.

   function Book_Loaded return Boolean;
   -- True when a book is currently loaded.

   function Probe (Position : in Position_Type; Move : out Move_Type)
     return Boolean;
   -- Pick a weighted random book move for Position. Returns False when the
   -- position is out of book or the entry is not legal (Move = Empty_Move).

end BBChess.Polyglot;
