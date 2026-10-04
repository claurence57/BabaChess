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
