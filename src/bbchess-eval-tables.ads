--
--  BabaChess : evaluation data -- parameters, piece values, PSTs
--
--  Everything the evaluation *reads* as a number: the tunable scalar table
--  (Params, one entry per P_* name) and the piece-square tables, stored from
--  each side's own point of view (row 0 = own back rank). The material+PST
--  flat table is precomputed here and kept in step by Rebuild_Material_PST
--  whenever a piece value changes.
--
--  The tuning interface (Set_Param / Load_Params / Dump_Params) lives with
--  the data it edits; BBChess.Eval re-exports it unchanged.
--

--  Piece, board and Score_Type are use-visible through the parent's context.

package BBChess.Eval.Tables is

   type PST_Table is array (Natural range 0 .. 7, Natural range 0 .. 7)
     of Score_Type;

   -- Per-row bonus table (passed pawns), indexed by the own row.
   type Row_Table is array (Natural range 0 .. 7) of Score_Type;

   -- Rows: 0 = own back rank, 7 = just before the opponent's back rank.
   Pawn_PST : PST_Table :=
     ((0, 0, 0, 0, 0, 0, 0, 0),
      (-16, -4, -4, -24, -24, -4, -4, -16),
      (-8, 0, 1, -6, -6, 1, 0, -8),
      (-8, -8, 1, 8, 8, 1, -8, -8),
      (4, 12, 6, 9, 9, 6, 12, 4),
      (16, 28, 30, 22, 22, 30, 28, 16),
      (12, 26, 4, 46, 46, 4, 26, 12),
      (0, 0, 0, 0, 0, 0, 0, 0));

   Knight_PST : PST_Table :=
     ((-42, -32, -14, -6, -6, -14, -32, -42),
      (-28, -4, 4, 4, 4, 4, -4, -28),
      (-26, 8, 10, 23, 23, 10, 8, -26),
      (2, 13, 15, 12, 12, 15, 13, 2),
      (-2, 8, 7, 20, 20, 7, 8, -2),
      (-22, 9, 10, 19, 19, 10, 9, -22),
      (-60, -40, -8, -7, -7, -8, -40, -60),
      (-98, -20, -50, -42, -42, -50, -20, -98));

   Bishop_PST : PST_Table :=
     ((-24, -2, -18, -6, -6, -18, -2, -24),
      (-10, 16, 8, 4, 4, 8, 16, -10),
      (-10, 4, 9, 2, 2, 9, 4, -10),
      (-18, -7, 1, 10, 10, 1, -7, -18),
      (-10, -8, 6, 6, 6, 6, -8, -10),
      (-10, 5, 1, 10, 10, 1, 5, -10),
      (-34, -12, -11, 10, 10, -11, -12, -34),
      (-32, -10, -14, -10, -10, -14, -10, -32));

   Rook_PST : PST_Table :=
     ((-12, -8, 16, 12, 12, 16, -8, -12),
      (-23, -2, 14, 2, 2, 14, -2, -23),
      (-5, 0, 0, 0, 0, 0, 0, -5),
      (-9, 0, 8, 8, 8, 8, 0, -9),
      (11, 12, 20, 16, 16, 20, 12, 11),
      (23, 16, 20, 36, 36, 20, 16, 23),
      (-7, -6, -6, -6, -6, -6, -6, -7),
      (32, 36, 28, 24, 24, 28, 36, 32));

   Queen_PST : PST_Table :=
     ((20, -2, 2, 11, 11, 2, -2, 20),
      (10, 4, 20, 16, 16, 20, 4, 10),
      (-6, 8, 9, 9, 9, 9, 8, -6),
      (-9, 0, -3, -3, -3, -3, 0, -9),
      (8, -20, 5, 1, 1, 5, -20, 8),
      (10, 29, 21, 17, 17, 21, 29, 10),
      (-10, -16, 9, 4, 4, 9, -16, -10),
      (-36, -2, 30, 23, 23, 30, -2, -36));

   -- Middlegame: the king belongs near its castled squares.
   King_PST : PST_Table :=
     ((16, 34, -2, 4, 4, -2, 34, 16),
      (38, 6, -16, -36, -36, -16, 6, 38),
      (-12, 28, -40, -36, -36, -40, 28, -12),
      (-78, -42, -46, -46, -46, -46, -42, -78),
      (-26, -14, -38, -46, -46, -38, -14, -26),
      (-6, 18, -38, -66, -66, -38, 18, -6),
      (-80, -24, -12, -4, -4, -12, -24, -80),
      (-88, -80, -16, -88, -88, -16, -80, -88));

   -- Endgame: the king must be active and central.
   King_End_PST : PST_Table :=
     ((-68, -51, -26, -25, -25, -26, -51, -68),
      (-35, -2, 7, 4, 4, 7, -2, -35),
      (-22, -13, 8, 13, 13, 8, -13, -22),
      (-14, 12, 17, 30, 30, 17, 12, -14),
      (26, 32, 37, 38, 38, 37, 32, 26),
      (30, 43, 40, 37, 37, 40, 43, 30),
      (21, 38, 43, 44, 44, 43, 38, 21),
      (-68, -63, 6, -53, -53, 6, -63, -68));

   -- Passed pawn bonus indexed by the pawn "own row" (0 = back rank).
   -- Row 0 and 7 are unreachable for a pawn, hence 0.
   Passed_Pawn_Opening : Row_Table :=
     (0, -7, -12, -20, -8, 14, 62, 0);
   Passed_Pawn_Endgame : Row_Table :=
     (0, 16, 14, 30, 48, 94, 162, 0);

   -- Tunable evaluation parameters (see the renames further down and the
   -- Set_Param / Load_Params / Dump_Params interface).
   type Param_Id is
     (P_Pawn, P_Knight, P_Bishop, P_Rook, P_Queen,
      P_Bishop_Pair_Op, P_Bishop_Pair_Eg,
      P_Mobility_N, P_Mobility_B, P_Mobility_R, P_Mobility_Q,
      P_Mobility_N_Eg, P_Mobility_B_Eg, P_Mobility_R_Eg, P_Mobility_Q_Eg,
      P_Rook7_Op, P_Rook7_Eg, P_Rook7_King,
      P_RookOpen_Op, P_RookOpen_Eg, P_RookSemi_Op, P_RookSemi_Eg,
      P_RookConn_Op, P_RookConn_Eg,
      P_Doubled_Op, P_Doubled_Eg, P_Isolated_Op, P_Isolated_Eg,
      P_Protected_Op, P_Protected_Eg, P_Outside_Op, P_Outside_Eg,
      P_Shield1, P_Shield2, P_Shield3, P_OpenFile, P_Storm,
      P_Atk_N, P_Atk_B, P_Atk_R, P_Atk_Q, P_Exposed,
      P_Threat_Pawn, P_Threat_Minor,
      P_Passed_Rear, P_Passed_Blocked, P_PKing_Them, P_PKing_Us,
      P_Scale_NoPawn,
      P_Mob_Area,
      P_KS_Lo, P_KS_Hi);

   type Param_Array is array (Param_Id) of Integer;
   Params : Param_Array :=
     (P_Pawn            => 100,
      P_Knight          => 320,
      P_Bishop          => 330,
      P_Rook            => 484,
      P_Queen           => 996,
      P_Bishop_Pair_Op  => 26,
      P_Bishop_Pair_Eg  => 57,
      P_Mobility_N      => 4,
      P_Mobility_B      => 6,
      P_Mobility_R      => 6,
      P_Mobility_Q      => 3,
      --  Endgame mobility weights, tuned independently of the opening ones.
      P_Mobility_N_Eg   => 2,
      P_Mobility_B_Eg   => 2,
      P_Mobility_R_Eg   => 6,
      P_Mobility_Q_Eg   => 9,
      P_Rook7_Op        => 3,
      P_Rook7_Eg        => 25,
      P_Rook7_King      => 37,
      P_RookOpen_Op     => 40,
      P_RookOpen_Eg     => -8,
      P_RookSemi_Op     => 22,
      P_RookSemi_Eg     => 16,
      P_RookConn_Op     => 10,
      P_RookConn_Eg     => 20,
      P_Doubled_Op      => 20,
      P_Doubled_Eg      => 7,
      P_Isolated_Op     => 8,
      P_Isolated_Eg     => 12,
      P_Protected_Op    => 36,
      P_Protected_Eg    => 48,
      P_Outside_Op      => -14,
      P_Outside_Eg      => 31,
      P_Shield1         => 12,
      P_Shield2         => 4,
      P_Shield3         => -3,
      P_OpenFile        => 8,
      P_Storm           => -1,
      P_Atk_N           => 12,
      P_Atk_B           => 12,
      P_Atk_R           => 2,
     P_Atk_Q           => 16,
     P_Exposed         => 4,
     P_Threat_Pawn     => 9,
     P_Threat_Minor    => 6,
     --  Passed pawns: 1 = the rear pawn of a doubled passer gets no passed
     --  bonus; Blocked = % of the row bonus kept when the stop square is
     --  occupied (100 = no effect); king proximity to the stop square, in
     --  eighths of a centipawn per square and per unit of the row weight.
     P_Passed_Rear     => 1,
     P_Passed_Blocked  => 56,
     P_PKing_Them      => 29,
     P_PKing_Us        => 16,
     --
     --  Mobility area was measured beneficial after the Texel tuning
     --  (DEVELOPMENT.md §73) and stays enabled.
     --
     --  Endgame scaling, out of 64 (P_Scale_NoPawn 0 = off). A lone minor
     --  with no pawn of its own can only win by a smothered mate, and the
     --  position is otherwise a draw (e.g. Kieseritzky-Jaenisch); Scale_Factor
     --  keeps a small residue when enemy pawns can still mate.
     P_Scale_NoPawn    => 1,
     --  1 = mobility ignores the squares attacked by enemy pawns.
     P_Mob_Area        => 1,
     --  King safety phase gate: full above Hi, none at or below Lo, linear
     --  in between. Hi <= Lo is the historical hard gate at Lo.
     P_KS_Lo           => 20,
     P_KS_Hi           => 20);

   function Piece_Value (Kind : in Kind_Type) return Score_Type;
   pragma Inline (Piece_Value);
   --  Material value of one piece kind (the tunable Params entries).

   function PST (Kind : in Kind_Type; Color : in Color_Type;
                 Square : in Square_Type) return Score_Type;
   pragma Inline (PST);
   --  Piece-square value of Square for a piece of Kind and Color.

   -- Flat (piece, square) table combining material and PST, precomputed at
   -- elaboration so the hot material loop is a single lookup per piece.
   type Piece_Square_Table is array (Piece_Type, Square_Type) of Score_Type;
   Material_PST : Piece_Square_Table := (others => (others => 0));

   -- Rebuild the flat material+PST table after a piece value changed.
   procedure Rebuild_Material_PST;

   -- Automatic tuning interface: the scalar constants are held in the Params
   -- table and can be overridden by name ("P_Mobility_N 5", and the PST
   -- entries as "P_PST_<T>_<row>_<file>").
   procedure Set_Param (Name : in String; Value : in Integer);
   procedure Set_Real_Param (Name : in String; Value : in Float);
   procedure Load_Params (File_Name : in String);
   procedure Dump_Params;

end BBChess.Eval.Tables;
