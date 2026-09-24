--
--  BabaChess : protocol layer self tests
--
--  Unit tests for the protocol layer that need no standard input and no real
--  search: the pure UCI / XBoard parsers, and the dispatch of the synchronous
--  commands (whose output is captured through an installed writing procedure).
--  Called from BBChess.Self_Tests.Run, so they run under "--selftest".
--

package BBChess.Protocol.Self_Tests is

   procedure Run;
   --  Run every protocol test; raises Program_Error on the first failure.

end BBChess.Protocol.Self_Tests;
