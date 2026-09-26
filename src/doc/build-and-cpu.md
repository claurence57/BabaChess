# Construction et optimisation CPU de BabaChess

Ce document décrit les **instructions de compilation** réellement utilisées et
l'**historique des optimisations CPU** (le levier de force prouvé du moteur).

## Makefile (sélection du CPU)

Un `Makefile` (racine) enveloppe `gprbuild`, dans l'esprit de celui de
RubiChess : il **détecte le CPU hôte** et choisit les commutateurs ISA, puis les
injecte via l'externe `BABA_ARCH_FLAGS` du projet (aucun flag codé en dur).

```bash
make                 # release, ISA auto-détecté
make checked         # vitesse release, contrôles runtime actifs (mode SPRT)
make portable        # x86-64 générique (repli PEXT logiciel)
make debug           # assertions + avertissements
make ARCH=native     # forcer -march=native
make ARCH=v3         # forcer un niveau x86-64 (v1..v4)
make ARCH=skylake    # forcer un nom -march= quelconque
make ARCH=generic    # aucun commutateur ISA (défaut du .gpr)
make test            # release + --selftest
make bench [DEPTH=9] # release + --bench
make info            # CPU détecté et commutateurs choisis
make clean
```

### Pourquoi des niveaux `x86-64-vN` et non `-march=native`

Le Makefile **n'utilise pas** `-march=native` par défaut. Mesures `--bench 11`
(25 passes appariées, min/médiane) sur le CPU de développement (Xeon E3-1270 v6,
Kaby Lake) :

| Variante | min (s) | médiane (s) |
|---|---|---|
| défaut `.gpr` (POPCNT/BMI/BMI2, `-mtune=generic`) | 0,4370 | 0,4577 |
| **`-march=x86-64-v3`** | **0,4298** | **0,4528** |
| `-mavx2` seul | 0,4283 | 0,4550 |
| **`-march=native`** (= `-mtune=skylake`) | 0,4481 | **0,4745** |

`-march=native` **ralentit d'environ 2,5 %** : il fixe aussi `-mtune=<ce CPU>`,
et `-mtune=skylake` est ici moins bon que `-mtune=generic`. Les **niveaux
`x86-64-vN`** (qui gardent `-mtune=generic`) sont neutres à légèrement
positifs. D'où le choix : détecter le meilleur niveau supporté et le passer en
`-march`.

Les jeux d'instructions ajoutés (`AVX2`, `FMA`, `LZCNT`, `ADX` en v3) **ne
changent pas l'arbre de recherche** : `--bench 9` = **518 612 nœuds** dans tous
les cas ; c'est du levier de **vitesse**, pas de force directement.

> **PGO non retenu.** Une passe `-fprofile-generate`/`-fprofile-use` a été
> essayée (faisable avec `-cargs`/`-largs`), mais mesurée **plus lente**
> (0,4955 s contre 0,4441 s en `--bench 11`) et fragile avec `-flto` : elle
> n'est **pas** proposée par le Makefile.

## Modes de construction

`babachess.gpr` expose le scénario `Mode` (`release` par défaut, `debug`,
`portable`, `checked`). Le binaire est écrit dans `bin/babachess`.

```bash
gprbuild -P babachess.gpr -XMode=release    # défaut : POPCNT/BMI2/PEXT, -flto
gprbuild -P babachess.gpr -XMode=checked    # vitesse release + contrôles actifs (SPRT)
gprbuild -P babachess.gpr -XMode=portable   # tout x86-64, repli PEXT logiciel
gprbuild -P babachess.gpr -XMode=debug      # assertions (-gnata), sans -gnatp
```

Le Makefile ne fait que choisir `Mode` et `BABA_ARCH_FLAGS` ; les commutateurs
ci-dessous restent la référence.

### Commutateurs exacts (GNAT + C)

| Mode | Ada (`Switches ("ada")`) | C (`Switches ("c")`) |
|---|---|---|
| **release** | `-gnat2012 -gnatp -gnatN -O3 -gnatf -gnatep=../src/prep.data -gnateDREL -mpopcnt -mbmi -mbmi2 -flto` | `-O3 -mpopcnt -mbmi -mbmi2` |
| **checked** | `-gnat2012 -gnata -gnatN -O3 -gnatf -gnatep=../src/prep.data -gnateDREL -mpopcnt -mbmi -mbmi2 -flto` | `-O3 -mpopcnt -mbmi -mbmi2` |
| **portable** | `-gnat2012 -gnatp -gnatN -O3 -gnatf -gnatep=../src/prep.data` | `-O3` |
| **debug** | `-gnat2012 -gnata -g -gnatep=../src/prep.data` | `-O0 -g` |

Chaque mode reçoit en plus `$(BABA_ARCH_FLAGS)` (externe, vide par défaut), que
le Makefile utilise pour ajouter le commutateur ISA du CPU (`-march=x86-64-v3`,
`-march=native`, …).

- `-gnatep=../src/prep.data` + `-gnateDREL` : **préprocesseur intégré** GNAT.
  `prep.data` ouvre la session avec `* -u` (symboles indéfinis = faux) ; `REL`
  n'est défini qu'en `release`/`checked`, donc `#if REL` sélectionne
  l'intrinsèque **PEXT** BMI2, `#else` le repli logiciel.
- `-gnatp` supprime les contrôles d'exécution (`release`/`portable`) → tout accès
  aux tampons doit être borné explicitement (`BBChess.Text`).
- `-flto` (Ada, `release` et `checked`) : édition de liens inter-unités. **Pas
  sur le C** : gprbuild archive les objets C avec `ar` et lie
  `libbabachess.a`, or le gprbuild FSF standard n'utilise pas `gcc-ar`, donc une
  archive bytecode LTO fait échouer le lien (`lto1: bytecode stream ... LTO
  version ...`) ; le C n'est pas sur le chemin chaud.
- **`checked`** : la vitesse de `release` (`-O3 -gnatN -flto`) **avec** les
  contrôles d'exécution (`-gnata`, sans `-gnatp`). Mesuré **≈ 11 % plus lent**
  que `release` (`--bench 11`, médiane), nœuds **identiques**. C'est le mode des
  **campagnes SPRT longues** ; `release` reste le mode de distribution.
- **portable** retire `-mpopcnt/-mbmi/-mbmi2/-flto` et laisse `REL` indéfini :
  tourne sur **tout x86-64**, avec le repli logiciel PEXT de `bbchess-bits.c`
  (≈ 25 % plus lent). C'est le mode à distribuer pour un CPU ancien.
- **Gotcha** : tous les modes partagent `obj/`. Après une construction d'un
  autre mode, faire `rm -rf obj` avant de rebâtir (et ne jamais comparer
  `--bench` entre deux modes sans rebuild propre).

### Alias du nombre de threads

Le nombre de threads Lazy SMP (1 à 16) se règle indifféremment par :

```bash
bin/babachess --threads 4      # argument séparé
bin/babachess -T4              # forme courte
bin/babachess --thread=4       # forme longue
```

Les formes `-T#` / `--thread=#` sont analysées par `BBChess.Text.Thread_Count`
(testée dans `--selftest`) ; toute valeur malformée retombe sur 1. En UCI,
`setoption name Threads value N` reste l'équivalent.

## Historique des optimisations CPU

Sept passes « sans changement de comportement » : l'arbre de recherche à
profondeur fixe est **bit-identique** (mêmes nœuds `--bench`), seule la vitesse
augmente. Détail complet dans `DEVELOPMENT.md` (§25, §30-31, §33, §36-37, §46).

| Passe | Changements principaux | Gain mesuré |
|---|---|---|
| 1 (§25) | PEXT inliné (préprocesseur GNAT), `Make_Move`/movegen, éval | **×1,59** vitesse |
| 2 (§30) | PEXT inliné, make/movegen, éval | −11,9 % instructions |
| 3 (§31) | chemin roi d'abord (movegen), SEE bitboard-only, éval | −12,2 % instructions |
| 4 (§33) | prefetch TT, sécurité roi/pions bitboard, hoists | −6,9 % instructions (×1,08) |
| 5 (§36) | suppression du tableau `Tac`, `Move_Piece` fusionné, `-flto` | −3,1 % instructions, −3,9 % cycles |
| 6 (§37) | entrée de TT 32 → 24 octets | −2,3 % cycles (×1,02) |
| 7 (§46) | `Poll_Time` scindé, test d'échec évité, `Suppress_Initialization` | −0,81 % instructions, −1,47 % cycles |

**Cumul** : ≈ **×2,3** de vitesse (`--bench 11` : ~1 360 → ~3 170 knps ; bench 9
0,56 → 0,25 s). Un SPRT « capstone » (300 parties, 1+0.1) entre le moteur actuel
et la baseline pré-optimisation vaut **+123 ± 31,6 Elo** (LOS 100 %) — le seul
levier de force **démontré** du moteur (§32).

## État : plus de gain facile, mais pas « rien à gagner »

Toutes les micro-optimisations **sûres** (arbre bit-identique) ont été
essayées ; les dernières passes rapportent **< 1 %** et le rendement décroît
nettement. Le profil reste dominé par `Negamax` (~39 %, **attente mémoire** de la
table de transposition), `Positional_Score` (~19 %) et `Generate_Legal_Common`
(~18 %). Les pistes restantes sont **non triviales et risquées** :

- **évaluation incrémentale** (mettre à jour les termes d'éval dans
  `Make_Move`/`Unmake_Move`) — la seule vraie réserve structurelle ;
- **réorganisation profonde du TT** (accès, buckets) — changerait les entrées
  acceptées, donc l'arbre.

Ces pistes exigent de **prouver l'identité** (nœuds `--bench` + éval
byte-identique sur des milliers de positions) et un **SPRT long** (≥ 600-1 000
parties) avant toute adoption. Les micro-ajustements restants rapportent trop
peu pour être distinguables du bruit.
