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
