# Campagne recherche (claude_search) — résultats bruts

Chaque test : paramètres seuls contre main, fastchess 4+0.04, 1000 parties max.

```
== s1b done Sun Oct  4 02:44:28 UTC 2026
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 13.56 +/- 16.24, nElo: 18.01 +/- 21.53
LOS: 94.94 %, DrawRatio: 38.40 %, PairsRatio: 1.17
Games: 1000, Wins: 345, Losses: 306, Draws: 349, Points: 519.5 (51.95 %)
Ptnml(0-2): [36, 106, 192, 115, 51], WL/DD Ratio: 2.00
LLR: 0.64 (21.8%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
== s2 done Sun Oct  4 03:29:25 UTC 2026
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 14.60 +/- 16.25, nElo: 19.39 +/- 21.53
LOS: 96.12 %, DrawRatio: 37.60 %, PairsRatio: 1.23
Games: 1000, Wins: 337, Losses: 295, Draws: 368, Points: 521.0 (52.10 %)
Ptnml(0-2): [38, 102, 188, 124, 48], WL/DD Ratio: 1.65
LLR: 0.70 (23.7%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

## Reprise (session du 4 octobre, après redémarrage du conteneur)

**Les deux résultats ci-dessus (s1b, s2) sont inexploitables** : le fichier de
paramètres de chaque test n'a pas été commité et a été perdu avec le
conteneur, on ne sait donc pas quelle fonction ils mesuraient. Ils ne sont pas
pris en compte. La campagne repart de zéro avec un protocole traçable :

- un fichier de paramètres **commité** par test : `campaign/params/<id>.params`
  (seuls les paramètres modifiés ; le reste = défauts compilés = `main`) ;
- un seul binaire pour les deux camps (`campaign/bin/babachess`, copie figée
  du HEAD indiqué) : « old » = défauts, arbre identique à `main`
  (`--bench 9` = 555 169) ; « new » = `--params <id>.params` ;
- fastchess 4+0.04, 1 thread, 4 parties simultanées, SPRT [0, 5] α = β = 0,05,
  plafond 1000 parties, chaque ouverture jouée dans les deux couleurs ;
- ouvertures `openings/ops.epd` (781 positions, commitées), générées par
  `scripts/expand_openings.py` (graine 1, deux demi-coups aléatoires,
  |éval| ≤ 70 cp à profondeur 7) ;
- lancement : `campaign/run.sh <graine> <id>...` ; chaque résultat est ajouté
  ci-dessous, commité et poussé **dès la fin du match**.

| Id | Fonction | Paramètres | `--bench 9` |
|---|---|---|---|
| t1_rfp | reverse futility jusqu'à prof. 6, marge +80/ply | `S_RFP_DEPTH 6`, `S_RFP_STEP 80` | 496 205 |
| t2_nmp_eval | null move seulement si éval ≥ beta | `S_NMP_EVAL 1` | 595 059 |
| t3_qs_tt | table de transposition en quiescence | `S_QS_TT 1` | 511 680 |
| t4_tm_stable | temps modulé par la stabilité du meilleur coup | `S_TM_STABLE 1` | 555 169 (temps seul) |
| t5_iir | réduction itérative interne dès prof. 4 | `S_IIR_DEPTH 4` | 560 672 |
| t6_bad_capture | captures SEE < 0 après les coups calmes | `S_BAD_CAPTURE 1` | 572 147 |
| t7_lmr_hist | LMR ± 1-2 ply selon l'historique (4000/ply) | `S_LMR_HIST 4000` | 513 908 |
| t8_asp_grow | fenêtre d'aspiration élargie progressivement | `S_ASP_GROW 1` | 501 832 |

Ordre : t1, t2 d'abord (les deux candidats probables de s1b/s2), puis t3-t8.
Tout terme positif sera **confirmé par une seconde série (autre graine)**
avant d'être retenu.

## Résultats traçables

### t1_rfp — graine 1 — bb93e74 — 2026-10-04 05:01:21 UTC

Paramètres (`campaign/params/t1_rfp.params`) : `S_RFP_DEPTH 6 S_RFP_STEP 80 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 39.43 +/- 16.90, nElo: 50.71 +/- 21.53
LOS: 100.00 %, DrawRatio: 35.60 %, PairsRatio: 1.62
Games: 1000, Wins: 358, Losses: 245, Draws: 397, Points: 556.5 (55.65 %)
Ptnml(0-2): [32, 91, 178, 130, 69], WL/DD Ratio: 1.02
LLR: 1.96 (66.4%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t2_nmp_eval — graine 1 — 22292c4 — 2026-10-04 05:48:31 UTC

Paramètres (`campaign/params/t2_nmp_eval.params`) : `S_NMP_EVAL 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 18.78 +/- 16.00, nElo: 25.34 +/- 21.53
LOS: 98.95 %, DrawRatio: 36.00 %, PairsRatio: 1.27
Games: 1000, Wins: 334, Losses: 280, Draws: 386, Points: 527.0 (52.70 %)
Ptnml(0-2): [31, 110, 180, 132, 47], WL/DD Ratio: 1.50
LLR: 0.94 (32.0%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

> **Incident (05:53 UTC)** : t3_qs_tt interrompu après 97 parties. Le runner
> t3-t8 avait été lancé comme processus détaché (`setsid nohup`) ; un tel
> processus ne maintient pas la session active et le conteneur a été recyclé
> peu après. Résultat partiel écarté. Correction : chaque lot de 2 matchs
> (≈ 95 min) tourne dans une tâche de fond suivie par la session (limite 2 h),
> relancée à la fin de la précédente. t3 repris à 08:21 UTC.

### t3_qs_tt — graine 1 — 1a66a81 — 2026-10-04 09:08:06 UTC

Paramètres (`campaign/params/t3_qs_tt.params`) : `S_QS_TT 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: -2.08 +/- 15.75, nElo: -2.85 +/- 21.53
LOS: 39.76 %, DrawRatio: 38.20 %, PairsRatio: 1.02
Games: 1000, Wins: 295, Losses: 301, Draws: 404, Points: 497.0 (49.70 %)
Ptnml(0-2): [42, 111, 191, 123, 33], WL/DD Ratio: 1.25
LLR: -0.22 (-7.5%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t4_tm_stable — graine 1 — d75b5a6 — 2026-10-04 09:54:45 UTC

Paramètres (`campaign/params/t4_tm_stable.params`) : `S_TM_STABLE 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: -1.04 +/- 16.48, nElo: -1.36 +/- 21.53
LOS: 45.06 %, DrawRatio: 32.80 %, PairsRatio: 0.98
Games: 1000, Wins: 313, Losses: 316, Draws: 371, Points: 498.5 (49.85 %)
Ptnml(0-2): [41, 129, 164, 124, 42], WL/DD Ratio: 1.78
LLR: -0.16 (-5.4%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t5_iir — graine 1 — f595fc3 — 2026-10-04 10:42:05 UTC

Paramètres (`campaign/params/t5_iir.params`) : `S_IIR_DEPTH 4 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 21.92 +/- 17.08, nElo: 27.73 +/- 21.53
LOS: 99.42 %, DrawRatio: 34.40 %, PairsRatio: 1.29
Games: 1000, Wins: 351, Losses: 288, Draws: 361, Points: 531.5 (53.15 %)
Ptnml(0-2): [40, 103, 172, 124, 61], WL/DD Ratio: 1.57
LLR: 1.04 (35.3%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t6_bad_capture — graine 1 — 33a51cb — 2026-10-04 11:29:29 UTC

Paramètres (`campaign/params/t6_bad_capture.params`) : `S_BAD_CAPTURE 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 52.87 +/- 16.76, nElo: 69.04 +/- 21.53
LOS: 100.00 %, DrawRatio: 33.60 %, PairsRatio: 1.94
Games: 1000, Wins: 400, Losses: 249, Draws: 351, Points: 575.5 (57.55 %)
Ptnml(0-2): [26, 87, 168, 148, 71], WL/DD Ratio: 1.90
LLR: 2.64 (89.8%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t7_lmr_hist — graine 1 — 8b5c473 — 2026-10-04 12:16:36 UTC

Paramètres (`campaign/params/t7_lmr_hist.params`) : `S_LMR_HIST 4000 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 0.69 +/- 16.91, nElo: 0.89 +/- 21.53
LOS: 53.21 %, DrawRatio: 33.80 %, PairsRatio: 0.98
Games: 1000, Wins: 313, Losses: 311, Draws: 376, Points: 501.0 (50.10 %)
Ptnml(0-2): [45, 122, 169, 114, 50], WL/DD Ratio: 1.41
LLR: -0.07 (-2.3%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t8_asp_grow — graine 1 — e1cd720 — 2026-10-04 13:03:06 UTC

Paramètres (`campaign/params/t8_asp_grow.params`) : `S_ASP_GROW 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: -16.69 +/- 16.81, nElo: -21.43 +/- 21.53
LOS: 2.55 %, DrawRatio: 34.40 %, PairsRatio: 0.79
Games: 1000, Wins: 287, Losses: 335, Draws: 378, Points: 476.0 (47.60 %)
Ptnml(0-2): [52, 131, 172, 103, 42], WL/DD Ratio: 1.39
LLR: -0.99 (-33.5%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t6_bad_capture — graine 2 — caca194 — 2026-10-04 13:50:18 UTC

Paramètres (`campaign/params/t6_bad_capture.params`) : `S_BAD_CAPTURE 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 50.38 +/- 16.15, nElo: 68.18 +/- 21.53
LOS: 100.00 %, DrawRatio: 35.60 %, PairsRatio: 1.98
Games: 1000, Wins: 393, Losses: 249, Draws: 358, Points: 572.0 (57.20 %)
Ptnml(0-2): [24, 84, 178, 152, 62], WL/DD Ratio: 1.92
LLR: 2.60 (88.4%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t1_rfp — graine 2 — 1a221e8 — 2026-10-04 14:38:05 UTC

Paramètres (`campaign/params/t1_rfp.params`) : `S_RFP_DEPTH 6 S_RFP_STEP 80 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 7.99 +/- 16.78, nElo: 10.27 +/- 21.53
LOS: 82.49 %, DrawRatio: 34.40 %, PairsRatio: 1.05
Games: 1000, Wins: 329, Losses: 306, Draws: 365, Points: 511.5 (51.15 %)
Ptnml(0-2): [39, 121, 172, 114, 54], WL/DD Ratio: 1.65
LLR: 0.32 (10.9%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t5_iir — graine 2 — 35dca74 — 2026-10-04 15:25:44 UTC

Paramètres (`campaign/params/t5_iir.params`) : `S_IIR_DEPTH 4 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 16.69 +/- 16.64, nElo: 21.65 +/- 21.53
LOS: 97.56 %, DrawRatio: 36.20 %, PairsRatio: 1.22
Games: 1000, Wins: 332, Losses: 284, Draws: 384, Points: 524.0 (52.40 %)
Ptnml(0-2): [38, 106, 181, 120, 55], WL/DD Ratio: 1.29
LLR: 0.79 (26.9%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

### t2_nmp_eval — graine 2 — 5d21296 — 2026-10-04 16:12:42 UTC

Paramètres (`campaign/params/t2_nmp_eval.params`) : `S_NMP_EVAL 1 `

```
Results of new vs old (4+0.04, 1t, 16MB, ops.epd):
Elo: 6.25 +/- 16.32, nElo: 8.26 +/- 21.53
LOS: 77.39 %, DrawRatio: 40.40 %, PairsRatio: 1.01
Games: 1000, Wins: 329, Losses: 311, Draws: 360, Points: 509.0 (50.90 %)
Ptnml(0-2): [38, 110, 202, 96, 54], WL/DD Ratio: 1.62
LLR: 0.24 (8.1%) (-2.94, 2.94) [0.00, 5.00]
--------------------------------------------------
```

## Bilan des deux séries et étape combinée

| Id | Graine 1 | Graine 2 | Verdict |
|---|---|---|---|
| t6_bad_capture | +52,9 ± 16,8 | +50,4 ± 16,2 | **confirmé** |
| t5_iir | +21,9 ± 17,1 | +16,7 ± 16,6 | **confirmé** |
| t1_rfp | +39,4 ± 16,9 | +8,0 ± 16,8 | non confirmé (≈ +24 sur 2000) |
| t2_nmp_eval | +18,8 ± 16,0 | +6,3 ± 16,3 | non confirmé (≈ +12 sur 2000) |
| t3, t4, t7 | ≈ 0 | — | rejetés (neutres) |
| t8_asp_grow | −16,7 ± 16,8 | — | rejeté |

Étape combinée (graine 3, `campaign/run.sh` accepte désormais `new:old`) :

| Id | Paramètres | Référence | `--bench 9` |
|---|---|---|---|
| c1_bad_iir | t6 + t5 | défauts | 450 242 |
| c2_c1_rfp | c1 + t1 | c1_bad_iir | 515 690 |
| c3_c1_nmp | c1 + t2 | c1_bad_iir | 513 639 |

c1 vérifie que t6 et t5 s'additionnent ; c2 et c3 mesurent ce que t1 et t2
apportent **en plus** de c1 (troisième mesure indépendante pour chacun).
