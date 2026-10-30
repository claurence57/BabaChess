# Archives PGN — évaluation Elo ancrée (2026-10-30)

Parties jouées par **BabaChess** contre un pool Stockfish à Elo nominal, et
utilisées pour l'estimation produite par `scripts/elo_rate.py`.

## Dispositif

- Moteur : **BabaChess `0511599`** (le moteur n'a plus changé depuis ; les
  commits d'outillage `be88b58` / `2e0f7bb` ne touchent que les scripts).
- Pool : `scripts/elo_pool.conf` — Stockfish `UCI_LimitStrength` + `UCI_Elo`
  à **1800, 2200, 2600, 3000**. C'est une échelle **auto-cohérente**, pas un
  rating CCRL officiel.
- Cadence : **10+0.1**, graine 7, concurrence 4.
- Ouvertures : `openings/openings.epd`, chaque ouverture jouée **deux fois**
  (couleurs inversées) ; livre désactivé des deux côtés.
- **200 parties par adversaire** (100 Blancs + 100 Noirs), soit **800 parties**.

## Résultats

Ordre **V-N-D** (victoires, nulles, défaites).

| Adversaire | Ancre | n | V-N-D | Score | Elo impliqué |
|---|---|---:|---|---:|---:|
| SF1800 | 1800 | 200 | 188-6-6 | 95,5 % | 2331 |
| SF2200 | 2200 | 200 | 163-7-30 | 83,2 % | 2479 |
| SF2600 | 2600 | 200 | 132-20-48 | 71,0 % | 2756 |
| SF3000 | 3000 | 200 | 9-33-158 | 12,8 % | 2666 |

**Estimation pooled (MLE ancré)** : 800 parties, **492-66-242** (65,6 %),
note **2655** — IC 95 % **2618 – 2693** (SE 18,9).

## Conclusion

- Sur l'échelle `Stockfish UCI_Elo`, BabaChess se situe **autour de 2600–2700**.
- ⚠️ Les Elo impliqués par ancre s'étalent de **2331 à 2756** : l'échelle
  `UCI_Elo` de Stockfish n'est pas linéaire/consistante vis-à-vis de BabaChess
  (et/ou il existe un effet de style). L'IC statistique (±19) **sous-estime**
  donc l'incertitude réelle ; compter **±150–200 Elo** de marge systématique.
- Ne comparer que des mesures faites **avec les mêmes ancres** ; ce n'est pas
  un rating CCRL officiel.

## Reproduction

```bash
scripts/elo_eval.sh --games 200 --tc 10+0.1 --concurrency 4 \
    --out /tmp/opencode/elo_eval
python3 scripts/elo_rate.py --pgn /tmp/opencode/elo_eval/*.pgn \
    --engine Baba --anchors scripts/elo_pool.conf
```

## Contenu de l'archive

`elo_eval_2026-10-30.zip` :

- `SF1800.pgn`, `SF2200.pgn`, `SF2600.pgn`, `SF3000.pgn` — 200 parties chacun ;
- `all.pgn` — concaténation des quatre (`cat SF*.pgn > all.pgn`).

SHA-256 de l'archive :
`d672c5d8e0c2376a4f78f2d42f13937aec224f44a22bb921bd4566ae764cb602`

Remarque : les `*.pgn` bruts sont ignorés par git (`.gitignore`) ; seule
l'archive ZIP est conservée dans le dépôt.
