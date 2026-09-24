# Notes de développement — BabaChess (ex-AdaChess-BB)

> **BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess).**
> Ce journal couvre le **chantier courant** (« solidité / propreté / performance »,
> P0-P7 et après, §48 à §62) : les sources vivent dans `src/`, le moteur se construit
> en `babachess.gpr` → `bin/babachess`, et le moteur **MB** a été retiré. Voir
> `NOTICE.md`.
>
> La partie **historique** (parcours pré-fork §1 à §47 : moteur **MB**, création et
> maturation du moteur **BB**) est déplacée dans **`DEVELOPMENT_HISTORY.md`**.
>
> **Développement assisté par IA.** Toutes les modifications apportées au projet
> depuis le fork initial ont été réalisées **avec l'aide d'agents IA** ; **aucun
> développement n'a été fait manuellement**. Modèle principal : **DeepSeek V4.1
> Flash** ; des corrections et compléments ont été apportés par des **prompts
> générés avec Claude** et **Kimi K3**. Outils de travail de base : **opencode**
> (plugin **oh-my-openagent**) et des **interfaces web**.

---

## 48. Chantier solidité / propreté / performance (P0-P7)

Chantier de **robustesse, propreté et performance** (aucun retuning, aucune
heuristique modifiée). Base `d2c8b4e` (v2.0). **Détail complet dans
`CHANGELOG_TECHNIQUE.md`** (et l'entrée P0-P7 de `CHANGELOG.md`). Filet de
sécurité à chaque étape : perft 1→5 = 20 / 400 / 8902 / 197281 / 4 865 609
**exact**, `--bench 9/11` = **496 570 / 1 434 292** nœuds **exacts**, `--selftest`
vert (release **et** portable **et** debug), `--dump-params` byte-identique.

**Trois propositions de la spécification corrigées après audit** (le détail mesuré
est dans `CHANGELOG_TECHNIQUE.md`) :

- **P0** : `bbchess-bits.c` **n'est pas mort** — `baba_pext` sert au build
  **portable** (`bbchess-attacks.adb`, `#else` de `#if REL`) ; le supprimer aurait
  cassé `-XMode=portable`. Seules `bb_popcountll`/`bb_ctzll` sont réellement
  inutilisées (Ada importe les `__builtin_*` directement) → retirées, fichier
  conservé.
- **P1** : `Squares (From)` non effacé n'est **pas** un bug — `Remove_Piece` ne
  l'efface pas non plus, `Squares` n'est lu qu'après test `All_Occ`, et
  `Piece_Type` n'a pas de « vide » → retenu : invariant **documenté** +
  `pragma Assert` (debug only).
- **P6** : l'index proposé (`6×64×64`) **change l'heuristique** (perd la case
  d'arrivée du coup précédent) → non livré. Seule la **largeur** est réduite à
  16 bits, **mêmes indices** : identité bit-à-bit, table 2,25 → 1,13 Mo.

**Validation (P7)** : perft + Kiwipete exacts ; SMP (profondeur 14, 1 vs 4 threads,
5 positions) sans crash et **scores plausibles** (2 bestmoves divergent mono/multi —
attendu en Lazy SMP, l'identité mono-thread étant garantie par `--bench`) ;
**SPRT 100 part. 10+0.1 vs `d2c8b4e` : NEW 23-21-56 (51,0 %), +6,9 ± 45,4 Elo,
LOS 61,8 % → neutre** (56 % de nulles) — aucune régression. **NPS global** :
`--bench 11` min de 7 runs entrelacés — **avant 0,5045 s** vs **après 0,5065 s
(−0,4 %, bruit)**. Chantier de solidité et de propreté, plus un gain SEE marginal.
**5 commits** P0→P6 (P3, P4 et P5 partagent un commit : hunks entrelacés).

---

## 49. Objectif final : le fork BabaChess (planifié)

**But** : quand il sera établi qu'on ne peut plus améliorer *sensiblement* les
performances du moteur, créer un **nouveau projet `BabaChess`** dans son propre
répertoire `~/BabaChess`. Le projet **rappellera explicitement qu'il est issu d'un
fork d'AdaChess**. Le développement se poursuivra alors **uniquement** sur
BabaChess.

**Licence** : **GPL** (comme AdaChess), **sauf** les parties en C reprises sous
licence **MIT**. Sont concernés aujourd'hui :
- `src/fathom/` — tablebases **Syzygy**, licence **MIT**
  (`src/fathom/LICENSE`, © Ronald de Man / basil00 / Jon Dart) ;
- `src/fathom/stdendian.h` — **MIT** (en-tête tiers dans Fathom) ;
- `src/bbchess-bits.c` — écrit pour ce projet (repli PEXT portable) : à
  confirmer au moment du fork (aucune mention MIT dans le fichier → a priori GPL,
  sauf décision contraire à ce moment-là).

**Condition de départ** : ne lancer BabaChess qu'après avoir **établi le seuil**
« plus d'amélioration sensible ». État actuel de ce constat :
- **CPU** : 7 passes « sûres » épuisées, dernières < 1 % (§46) ; réserves
  structurelles (éval incrémentale, refonte TT) non ouvertes.
- **Recherche/éval** : gains confirmés par SPRT long = ordonnancement
  counter‑move/history (§40, +22) et gestion du temps (§41, +50) ; le reste
  (SPSA, Texel, SE, ProbCut, multi‑cut, outposts, modulateurs LMR, etc.) est
  **neutre ou négatif** (§§13‑44).
- **Reste à trancher** : les deux réserves structurelles ci‑dessus n'ont pas
  encore été tentées avec un SPRT long ; tant qu'elles ne le sont pas, le seuil
  « plus d'amélioration sensible » n'est pas **établi**.

Rien n'est encore créé : pas de répertoire `~/BabaChess`, pas de fork. Ceci
n'est que la **planification** de l'étape suivante.

### 49.1 Réserve structurelle (a) — évaluation incrémentale : NON RENTABLE

Étude de faisabilité (mesure `perf` + analyse). Conclusion **négative et
documentée** :

- `Evaluate` ≈ **23 % des cycles**, et **~65‑70 % de `Positional_Score`** est le
  chemin **mobilité / génération d'attaques / popcount**, **structurellement
  non‑delta‑able** (chaque coup modifie l'occupation).
- Le résidu réellement incrémentable en **byte‑identique** (paire de fous, tours
  connectées, PST du roi, agrégats de pions simples) ne pèse que **≈ 1‑2,5 %** du
  temps — **moins que le surcoût de comptabilité** ajouté dans
  `Make_Move`/`Unmake_Move`.
- L'identité byte‑exacte *serait* atteignable (accumulation entière exacte,
  troncature par terme + `Blend` final), mais la répartition des coûts **tue le
  gain**.

⇒ **Non implémenté** (aucun prototype), gate respecté. Le matériel+PST est
**déjà** incrémental (`Position.Material`) ; le reste n'a pas de delta rentable.
Fichiers inchangés (`--bench` 496 570/1 434 292 exacts, `--selftest` vert).

**Conséquence pour le seuil** : la réserve (a) est **écartée sur la foi de
mesures**. Reste la réserve (b) — refonte du TT — pour trancher.

### 49.2 Réserve structurelle (b) — refonte TT : AUCUN GAIN

Étude de faisabilité (mesure `perf` + prototype). Conclusion **négative et
documentée** :

- **Coût TT attribuable** : `--bench 12` → LLC-load-misses **326 K** (0,127/nœud),
  soit ≈ 75 M cycles = **2,3 % du total** au *maximum absolu* (en supposant tous
  les misses LLC imputables au TT) ; **≈ 1 %** réaliste. Plafond de tout gain TT
  **≈ 2‑3 %, réalistement ~1 %**.
- **Balayage de taille de table (arbre identique)** : 6 Mo (‑4×, réside en L3) →
  **+1,2 %** ; 24 Mo → référence ; 48 Mo (2×) → **+1,4 %**. Diviser la table par 4
  **divise les LLC-miss par 2** (326 K → 168 K) **sans aucun gain de vitesse** →
  le TT est **insensible à la latence** ; ni capacité ni layout ne sont le goulot.
- **Prototype bucket 4 voies** (24 Mo) : arbre quasi inchangé (1 434 281 vs
  1 434 292) et **−2,6 à −3,4 % (régression)** — la sonde élargie coûte plus que
  les évictions qu'elle évite.
- Le « `Negamax` 39 % » du profil est **le corps de nœud entier** (movegen/éval
  inlinés), **pas** l'accès mémoire au TT.

⇒ **Aucun gain ; SPRT non justifié ; refonte non adoptée.** La conception actuelle
(2 voies / 24 Mo / profondeur‑préférée + aging) est **déjà à l'optimum mesuré**.

### 49.3 Seuil « plus d'amélioration sensible » : ÉTABLI

Les **deux** réserves structurelles sont désormais **écartées sur mesures**
(§49.1 éval incrémentale : résidu byte‑exact ≈ 1‑2,5 % < surcoût ; §49.2 refonte
TT : plafond ~1 %, le 4‑voies régresse de 3 %). Avec, par ailleurs :

- **7 passes CPU** « sûres » épuisées (dernières < 1 %, §46) ;
- **toutes** les pistes recherche/éval testées (SE, ProbCut, multi‑cut, outposts,
  modulateurs LMR, move picker, tri SEE, Texel, SPSA‑éval et SPSA‑recherche) :
  **neutres ou négatives** ; seuls gains confirmés = ordonnancement
  counter‑move/history (§40, +22 Elo) et gestion du temps (§41, +50 Elo), **déjà
  intégrés** ;

le constat **« on ne peut plus améliorer sensiblement les performances »** est
**établi**. ⇒ Condition de départ de **BabaChess remplie** (§49) : le fork peut
être créé (`~/BabaChess`, mention d'origine AdaChess, GPL + parts C MIT).

## 50. Audit externe (Oracle) et correctifs de recherche — gain confirmé

Un audit externe du moteur BabaChess (analyse multi-agents + revue Oracle) a
relevé une série de défauts de correction et de robustesse, ensuite validés
individuellement puis en lot. Les correctifs ont été appliqués dans le commit
`98c48ee` (moteur) et `78353cb` (README) ; ils ne touchent **ni** le générateur
de coups **ni** les perft.

### 50.1 Correctifs retenus (commit `98c48ee`)

- **Répétition vers la position racine** (`bbchess-search.adb`) : la détection
  scannait les plies `1 .. Ply-1` et comptait la racine dans l'historique de
  partie (`G = 1`), jamais `≥ 2` : une ligne revenant à la racine n'était pas
  vue comme nulle. `Search_Path (0)` est désormais écrit au départ de
  `Iterative_Search` et la borne basse passe à `0`. Corrige aussi une **lecture
  hors bornes** latente (`Ply > Max_Ply` sous extensions d'échec) via la borne
  `Natural'Min (Ply - 1, Max_Ply)`.
- **Garde-fou null-move** : interdiction de deux null-moves consécutifs
  (atteignable dès `Depth ≥ 9`), via `Prev /= Empty_Move` (le bloc null remet
  déjà le slot `Move_Path (Ply)` à vide).
- **Course TT (Lazy SMP)** : la sonde **copie l'entrée puis teste la clé sur la
  copie** (au lieu de tester la clé du slot vivant avant la copie), ce qui
  empêche une écriture concurrente de faire utiliser la charge utile d'une autre
  clé. Le commentaire de `Store` (« clé écrite en dernier ») est corrigé : il
  surestimait la protection. La fermeture complète (fenêtre ABA) demanderait un
  schéma « key xor data » ou un compteur de version (non fait ici).
- **Interblocage des workers** (`task body Searcher`) : un handler `when
  others =>` garantit que `Done.Signal` est toujours atteint ; sans lui, une
  exception inattendue laissait `Done.Wait_All` bloqué à vie.
- **Handler d'exception du `UCI_Search_Task`** (`babachess.adb`) : libère
  `UCI_Busy` et répond `bestmove 0000`, évitant une GUI figée et un
  `Tasking_Error` au `go` suivant.
- **Double `bestmove`** : le chemin livre est sauté si une recherche tourne
  (`not UCI_Busy.Busy`), au lieu d'imprimer un `bestmove` de livre pendant que
  l'ancienne recherche imprime le sien.
- **Mat vs règle des 50 coups** : au 100ᵉ demi-coup, le nul n'est pris qu'après
  vérification de l'absence de mat (le camp au trait en échec sans coup légal
  vaut `-(Mate_Score - Ply)`). Le test de nul reste **avant** la sonde TT (la clé
  Zobrist ne porte pas le compteur de demi-coups).
- **`go nodes` multi-thread** : plafond divisé par le nombre de workers
  (snapshot), pour ~N nœuds au total.
- **FEN** (`bbchess-fen.adb`) : rejet d'un `/` interne, d'un rang qui ne fait
  pas exactement 8 cases, d'un séparateur manquant et de tout contenu après le
  8ᵉ rang. **Faux positifs écartés** : l'accès hors bornes annoncé n'était pas
  possible (la boucle ne pose une pièce que si `File ≤ 7`).
- **Commentaire Syzygy** rectifié (`rule50` forcé à 0, case ep transmise).

### 50.2 Validation

- `--bench 9` = **496 570 nœuds**, identique à la référence : l'arbre
  mono-thread est préservé (les correctifs n'agissent que sur le multi-thread et
  sur les cas limites).
- `--selftest` vert en `release`, `portable` et `debug` (0 avertissement en
  debug).
- **SPRT long** (1+0,1 ; bornes 0..5 ; 2000 parties max ; seed 7 ; binaire
  pré-patch `7f4f32e` en OLD) : **NEW 521 – OLD 405 – 915 nulle (53,2 %)**,
  **+21,9 ± 11,2 Elo**, LOS 100 %, LLR 2,95 ≥ ubound 2,94 ⇒ **PASS**.
  Le patch est **non régressif et plus fort** (le gain vient surtout de la
  répétition racine, de la priorité mat et de l'interdiction du double
  null-move).

### 50.3 Restant (audit externe)

Traité dans des commits dédiés (`6d98989`, `9c6d3be`, `c81d6ee`, `6cf1c44`,
`e3f349a`) :

- **Compteurs de nœuds** : passés en 64 bits (`Node_Count_Type`, 0 .. 2⁶²) —
  fin du dépassement silencieux sous `-gnatp` et de la perte du
  `stop`/budget temps au-delà de 2³¹ nœuds (`9c6d3be`).
- **TT auto-vérifiante** : entrée « key xor data » en deux mots `Atomic`
  (Data 64 bits + Key_Xor) — ferme la course ABA ; table 24 → 16 Mo
  (`6cf1c44`).
- **Sortie UCI `info`** : `depth/score/nodes/nps/pv`, avec score `mate` et
  extraction de la PV depuis la TT (`c81d6ee`).
- **SEE** : reprise par le roi sur une case encore défendue — **corrigé**,
  voir §51 (`e3f349a`).
- **En-tête `bbchess-attacks.ads`** : « fancy magic » → « PEXT (BMI2) lookup »
  (`6d98989`).

Tous ces lots gardent `--bench 9` à **518 612 nœuds** (arbre mono-thread
inchangé, sauf le SEE de §51 qui modifie l'élagage : 496 570 → 518 612) et
`--selftest` vert dans les trois modes.

### 50.4 Restant (audit externe, non traité)

- Discontinuité de `King_Safety` au seuil `Phase = 20` — **bloqué par le
  moratoire** de §17 (deux refontes déjà régressives) ; ne pas y toucher sans
  modèle plus fin + auto-tuning validé SPRT.

## 51. SEE — reprise par le roi sur une case encore défendue (bug corrigé)

### 51.1 Le bug

Dans `bbchess-see.adb`, la passe avant de `Exchange` générait la séquence de
prises ; quand l'attaquant le plus faible était le **roi**, la prise était
comptée comme terminale (`King_Last`) **sans vérifier qu'elle est légale**. Or un
roi ne peut pas capturer sur une case encore attaquée par l'adversaire (FIDE
3.1.3) — y compris une attaque qui n'apparaît qu'**après** le départ du roi,
par rayons X, et par une pièce qui serait clouée (une pièce clouée défend
toujours).

Reproduction (test ajouté au `--selftest`) :

- FEN `8/8/4k3/3p4/3Q4/8/8/3R2K1 w - - 0 1`, coup **Qd4xd5** : après Dxd5, la
  tour d1 défend d5 par rayons X, donc **Kxd5 est illégal** ; la valeur SEE
  correcte est **+100** (le pion gagné). L'ancien code renvoyait **−800** (dame
  perdue), comme si le roi pouvait reprendre.
- FEN `8/8/4k3/3p4/3Q4/8/8/6K1 w - - 0 1` (sans la tour), **Kxd5 est légal**,
  valeur **−800**.

**Conséquence** : des captures gagnantes près du roi adverse pouvaient être
élaguées en quiescence (SEE < 0), c'est-à-dire des coups réellement bons rejetés.

### 51.2 Correctif (commit dédié)

- Nouvelle fonction locale `Attacked (B, To, By)` : vraie si `To` est attaquée
  par une pièce de `By`, **sans** filtre d'épingle (une pièce clouée attaque).
  Elle travaille sur l'occupation du plateau de travail `See_Board`, donc les
  rayons X sont vus correctement (la pièce qui vient de partir a été retirée).
- Dans `Exchange`, quand `Att = Roi` : après avoir posé le roi sur `To`, si
  `Attacked (B, To, Opposite (Side_Now))` alors la reprise est illégale → on
  **annule l'étape** (`Count - 1`), on n'active pas `King_Last`, et on sort. La
  valeur retombe donc sur celle du dernier camp à avoir réellement pris.
- `--selftest` : les **5 cas SEE existants restent verts** ; les **2 nouveaux
  cas** (`Qxd5` → +100 avec la tour, −800 sans) sont ajoutés.

### 51.3 Validation honnête — bug corrigé, effet Elo NON prouvé

- `--selftest` vert (release/portable/debug, 0 avertissement) ; les perft sont
  inchangés (le SEE n'entre pas dans le movegen).
- `--bench 9` = **518 612 nœuds** (vs 496 570 avant) : l'arbre change, c'est
  attendu — l'élagage SEE de la quiescence est modifié.
- **SPRT long** (1+0,1 ; bornes 0→5 ; 2000 parties ; seed 7 ; binaire
  pré-correctif en OLD) :

  | métrique | valeur |
  |---|---|
  | parties | **2000** (plafond atteint) |
  | score NEW vs OLD | **620 – 541 – 839** → **52,0 %** |
  | Elo | **+13,7 ± 11,6** |
  | LOS | **99,0 %** |
  | LLR final | **+1,60** (bornes −2,94 / +2,94) |
  | verdict | **INCONCLUSIVE** |

  Lecture : le LLR est resté **positif tout du long** (+0,4 à +1,6), l'estimation
  est ~**+14 Elo** avec ~**99 % de chance que le signe soit positif** — mais
  l'intervalle (`+13,7 ± 11,6`) est trop large pour **prouver** un effet ≥ 5 Elo
  (le LOS seul ne prouve pas la taille de l'effet). Aucune trace de régression.

**Décision** : le correctif est **conservé** parce qu'il corrige un **vrai bug**
démontré (roi prenant une case défendue, élagage de captures gagnantes) et que
les tests le verrouillent. Le gain de force est **plausible mais non établi** —
il n'est donc pas présenté comme acquis. La règle « l'important est de corriger
les bugs, pas de gagner des points Elo » a guidé ce choix.

## 52. Revue externe approfondie et correctifs sûrs

Une seconde revue externe (indépendante, sur le commit `8ab4871`) a produit un
rapport détaillé et un patch. Chaque constat a été **revérifié ici** (reproduction
du bug puis test du correctif) avant adoption.

### 52.1 Bloc sûr (commits `67cc5ea`, `a77bd4f`) — arbre bit-identique

`--bench 9/11/12` = **518 612 / 1 286 807 / 2 358 722** (inchangés),
`--selftest` vert en debug et release.

| Id | Correctif |
|---|---|
| **B1** | **Syzygy** : ne sonder le WDL qu'après un coup irréversible (`Halfmove = 0`). Avant, chaque coup gagnant valait `TB_Win - 1` et l'itération s'arrêtait : le moteur **perdait des finales gagnées** (vérifié : KQvK passait de `cp 19999` à profondeur 2 à une recherche normale). |
| B3 | UCI : `score cp -558` et `score mate -N` (l'`Image` d'un négatif n'a pas d'espace de tête ; on l'enlève et on ajoute l'espace). |
| B4 | UCI : en `go infinite`, `bestmove` n'est émis qu'après `stop`. |
| B5 | UCI : `go depth N` sans pendule n'est plus coupé à 1 s. |
| B6 | FEN : validation matérielle (≤ 8 pions, aucun en rang 1/8, promotions bornées par les pions manquants). Une FEN hostile (**29 dames**) corrompait la pile et **plantait** en release `-gnatp` ; désormais `bad FEN`. |
| B7 | UCI : `position fen <courte> moves …` n'oublie plus les coups (on cherche le jeton `moves` au lieu de supposer le rang 8). |
| B8 | Polyglot : décodage des roques (« roi prend sa tour ») — un roque du livre est désormais joué. |
| B10 | `Insufficient_Material` : couleur d'une case = `(colonne + rang) mod 2`, pas `index mod 2`. |
| B11 | XBoard : clés de partie enregistrées en mode force ; `feature memory=1` (mensonger) retiré ; `sigint=0 sigterm=0`. |
| B12 | Tâche UCI : ajout de `or terminate` (la boucle principale ne peut plus se figer). |
| B14 | TT : comparaison d'âge par `/=`, robuste au repli à 2¹⁵. |
| B15 | `Exact(0)` (`movetime 0`/`st 0`) : plancher, pour rester interruptible. |
| B16 | `Trim_Both` retire aussi `CR` (entrée CRLF tolérée). |
| B19 | `position … moves` : un coup invalide stoppe l'application (plus de désynchronisation). |
| B20 | `setoption` destructif (Hash/Clear Hash/BookFile/SyzygyPath) ignoré pendant une recherche (`tb_init` sous une sonde = use-after-free C). |

### 52.2 Traités en lots SPRT séparés (changement d'arbre)

- **B9** — élagage de frontière aveugle aux échecs (RFP/LMP/futility) : test
  d'échec après `Make_Move` ; un coup donnant échec n'est plus élagué.
  `--bench 9` **518 612 → 607 956** (+17 %). **REJETÉ** : SPRT arrêté à
  **628 parties**, NEW **50,6 %** (190 – 183 – 255), LLR **+0,12** — neutre,
  pour un coût d'arbre de +17 % et un gain nul. Le lot n'est pas committé
  (correctif conservé dans `/tmp/opencode/b9.patch`, non adopté).
- **B2** — plafond de temps proportionnel à la pendule (`Max_Soft` absolu de 2 s
  faisait ignorer la pendule dès les cadences moyennes). Correctif **vérifié
  fonctionnellement** : `go wtime 200000` donne `bestmove` à **2054 ms** (OLD,
  plafonné) vs **4906 ms** (NEW), depth 17 → 19. **SPRT INCONCLUSIVE** à
  **60+0,6, 400 parties** : NEW **48,1 %** (70 – 85 – 245), `-13,0 ± 21,2` Elo,
  LOS 11,4 %, LLR **−0,67** (bornes ±2,94), **0 forfait au temps**. Nuance
  importante : à 60+0,6 le correctif n'agit qu'en **transitoire** (2,00 → 2,45 s,
  puis les deux convergent vers le même équilibre `Clock* = 7,5·Inc = 4,5 s`),
  donc ce résultat mesure surtout du bruit ; la pathologie visée (incrément qui
  **fait grossir** la pendule, ex. 900+10) n'est pas testable économiquement.
  Par la règle du projet, un non-PASS ⇒ **non committé** ; correctif prêt
  (`/tmp/opencode/batches/b2_full.patch`, avec test de non-régression).
- **B18** — null-move renvoyant un score de mat non prouvé : borne. `--bench
  9/11/12` **bit-identique**, et la branche est **rare** (mesurée par
  instrumentation : **0** déclenchement sur bench 9/11/12 et 5 positions de mat,
  **4** sur les 40 positions de `bench/diag.tsv` à depth 12). **SPRT
  INCONCLUSIVE** à **1+0,1, 2000 parties** : NEW **51,0 %** (610 – 568 – 822),
  **+7,3 ± 11,7** Elo, LOS **88,9 %**, LLR **+0,68** (bornes ±2,94), 0 forfait.
  Tendance positive mais sous le seuil : par la règle du projet, **non
  committé** (correctif prêt dans `/tmp/opencode/batches/b18.patch`).

**Bilan des trois lots SPRT** : aucun n'atteint le PASS requis — **B9 neutre et
coûteux (rejeté)**, **B2 INCONCLUSIVE (bénéfice long-TC non mesurable ici)**,
**B18 INCONCLUSIVE à tendance positive (bug rare)**. Conformément à la règle
« un non-PASS ne se committe pas », aucun n'est intégré ; les trois correctifs
sont conservés hors arbre et documentés.

### 52.3 Corrigé sans SPRT (arbre inchangé)

- **B17** — compteurs `info nodes`/`nps` mono-thread en SMP : compteur global
  `SMP_Nodes` (atomique, incrémenté dans `Poll_Time_Slow`). Purement affichage :
  l'arbre est inchangé (`--bench 9` = 518 612), validé par inspection
  (4 threads depth 10 : 150 528 nœuds au lieu de ~39 000). Commit `b6b41f0`.

## 53. Mode de build `checked` (vitesse release + contrôles runtime)

`release` et `portable` compilent avec `-gnatp`, qui **supprime tous les
contrôles d'exécution**, combiné à `-gnatN -O3 -flto`. Avec seulement 5
`pragma Assert` (actifs en `debug` uniquement), un dépassement d'indice ou de
`Score_Type` devenait un comportement indéfini silencieux en production.

### 53.1 Le mode

`babachess.gpr` gagne un quatrième mode `checked` : **identique à `release`**
(`-O3`, `-gnatN`, `-flto`, préprocesseur `REL`, mêmes commutateurs ISA) **mais
sans `-gnatp` et avec `-gnata`** — assertions, contrôles de plage et d'indice
actifs. Exposé par `make checked` et par la CI (build + `--selftest`).

### 53.2 Coût mesuré

`--bench 11`, 15 runs appariés entrelacés (min et médiane) sur le CPU de
développement :

| | min (s) | médiane (s) | nœuds |
|---|---|---|---|
| `release` | 0,4320 | 0,4545 | 1 286 807 |
| `checked` | 0,4814 | 0,5063 | 1 286 807 |
| **delta** | **+11,4 %** | **+11,4 %** | **identiques** |

Le nombre de nœuds est **strictement identique** (les contrôles ne changent pas
l'arbre) ; le surcoût est du temps CPU. `--selftest` vert en `checked`.

### 53.3 Convention d'usage

- **`checked` est le mode à utiliser pour toutes les campagnes SPRT longues** :
  comportement défini au lieu d'un comportement indéfini silencieux si un
  invariant venait à être violé.
- **`release` reste le mode de distribution** (binaire le plus rapide).
- `debug` reste le mode des avertissements (`-gnatwa`), `portable` celui du
  repli PEXT pour CPU sans BMI2.

Conséquence pratique : un SPRT en `checked` est ~11 % plus lent à cadence de
temps fixe ; pour comparer deux binaires, les deux doivent être `checked` (ou
tous deux `release`), jamais un de chaque.

## 54. Contrats Ada 2012 (P0.3)

Le projet n'avait jusqu'ici **aucun** contrat (`Pre`, `Post`, `Type_Invariant`).
Le cœur de la représentation (cohérence mailbox `Squares` ↔ bitboards) était
décrit en prose dans les commentaires, jamais exprimé au compilateur. Ce
chantier ajoute les contrats là où ils sont à la fois **utiles et sûrs**.

### 54.1 Ce qui a été ajouté

- **`Pre` sur `Make_Move`** (`bbchess-moves.ads`) : `From /= To`, la pièce du
  coup est bien sur la case de départ, et la case d'arrivée n'est pas occupée
  par une pièce amie. C'est la partie *structurelle* du « pseudo-légal ».
- **`Pre` sur `Unmake_Move`** : `From /= To`, le trait est bien l'adversaire du
  joueur du coup (il a été inversé par `Make_Move`), et la case d'arrivée est
  occupée.
- **`Pre` sur `Static_Exchange_Value`** (`bbchess-see.ads`) : `From /= To` et,
  hors promotion, la pièce est sur la case de départ.
- **`Post` sur `Generate_Pseudo_Moves`** (`bbchess-movegen.adb`) : `Count <= 256`
  et `King_First in 1 .. Count + 1` — le générateur n'écrit jamais au-delà du
  tampon `Move_List` (contrat dont dépend le build `release` sans `-gnatp`).

### 54.2 Coût nul en release

Les contrats ne sont compilés que sous `-gnata` (modes `debug` et `checked`).
`release` et `portable` (sans `-gnata`) les **éliminent entièrement** : vérifié
par `--bench 9` = 518 612 et `--bench 12` = 2 358 722 nœuds, **identiques** à
avant le chantier, et par `--bench 11` en release dont le temps reste dans le
bruit de mesure (< 1 %). En `debug` et `checked`, `--selftest` reste vert : les
préconditions sont donc bien satisfaites par tout le code existant.

### 54.3 Pourquoi pas un `Type_Invariant` sur `Position_Type`

La demande initiale était un `Type_Invariant` sur `Position_Type` (cohérence
mailbox ↔ bitboards, un roi par camp, occupation = union des bitboards).
**Ada l'interdit** : `Type_Invariant` n'est autorisé que sur un type **privé**
(erreur GNAT vérifiée : *« only allowed for private type or corresponding full
view »*). Or `Position_Type` est **public** et ses champs sont lus/écrits
directement partout : ~395 accès dans 13 fichiers, dont le chemin chaud de la
recherche. Le privatiser proprement relève du chantier P1.4 (encapsulation de la
représentation), pas de P0.3.

L'ersatz disponible sur un type public, `Dynamic_Predicate`, a été mesuré puis
écarté :

- il est vérifié **à chaque frontière de sous-programme** (entrée et sortie) ;
- la version complète (mailbox 64 cases + couleurs + deux rois) fait passer
  `--bench 11` en `checked` de **0,53 s à 1,30 s (~2,6×)**, ce qui détruirait le
  mode SPRT que §53 vient précisément de créer ;
- même la version réduite à l'occupation seule coûte déjà ~9 % ;
- surtout, un `Dynamic_Predicate` sur le *type* se déclenche sur les états
  intermédiaires **légitimes** : le champ global `Root_Position : Position_Type;`
  (initialisé vide, `bbchess-search.adb:2285`) et les `Position_Type` locaux par
  défaut pendant la construction (`Load`, `Start_Position`, `Put_Piece`
  incrémental). Le contrat aborte donc au démarrage de `--selftest`.

Ces contrats seront donc revisités **après** P1.4, une fois `Position_Type`
privatisé : un vrai `Type_Invariant` deviendra alors possible, appliqué aux
seuls constructeurs/mutateurs plutôt qu'à chaque appel (la forme correcte pour
un invariant de type, et gratuite à l'exécution hors `-gnata`).

## 55. Extraction de la couche protocole (P1.1)

`babachess.adb` était une procédure de **1 180 lignes** mêlant le protocole UCI,
le protocole XBoard, la gestion d'horloges, le livre d'ouvertures, le parsing de
la ligne de commande et la lecture directe de `stdin`. Aucun de ces chemins
n'était testé. Ce chantier extrait la couche protocole dans des paquets dédiés.

### 55.1 Découpage

| Unité | Lignes | Rôle |
|---|---|---|
| `BBChess.Protocol` | 825 (corps) | état de session + dispatch + tâche de recherche UCI asynchrone |
| `BBChess.Protocol.UCI` | 118 | parsers purs `go` / `setoption` |
| `BBChess.Protocol.XBoard` | 84 | parser pur `level` / `time` |
| `BBChess.Protocol.Self_Tests` | 274 | tests unitaires de la couche |
| `babachess.adb` | 256 (était 1 180) | modes CLI + boucle mince de lecture |

Les 20 clauses `with` de `babachess.adb` tombent à **13**.

### 55.2 Le contrat « une ligne → une réponse » n'est pas littéral

La consigne demandait une API prenant une ligne et **retournant** une réponse,
découplée de `Text_IO`. C'est impossible tel quel, pour une raison de fond : la
recherche UCI est **asynchrone**. Un `go` lance la recherche dans une tâche qui
émet son `bestmove` (et la recherche ses lignes `info`) **après** le retour du
traitement, et `isready` doit répondre `readyok` pendant que cette tâche tourne.
Une valeur de retour ne peut pas transporter une sortie produite plus tard par
une autre tâche, et un tampon borné ne peut pas porter un handshake multi-ligne.

Le compromis fidèle retenu : un **callback d'écriture** (`Line_Writer`). Les
paquets `BBChess.Protocol.*` ne touchent jamais `Ada.Text_IO` ; chaque ligne
sortie passe par le writer installé par l'appelant. En production c'est
`BBChess.Search.Locked_Put_Line` — le **même verrou console** que la tâche de
recherche, donc les réponses du protocole et les `info`/`bestmove` ne peuvent
pas s'entrelacer. En test, c'est un writer capturant, ce qui rend le dispatch
vérifiable **sans `stdin` ni recherche**. La partie réellement « ligne → valeur »
est constituée par les parsers purs (`Protocol.UCI`/`.XBoard`).

### 55.3 Iso-comportement vérifié

- `debug` : 0 avertissement.
- `--selftest` vert en `debug`, `checked`, `release` et `portable`, avec les
  nouveaux tests protocole.
- Nœuds `--bench 9/11/12` = 518 612 / 1 286 807 / 2 358 722, **identiques**.
- Transcripts UCI et XBoard **octet pour octet identiques** (hors champs
  temporels `time`/`nps`), y compris sur les cas malformés et le cas
  asynchrone `go infinite` + `isready` + `stop` (le `readyok` apparaît bien au
  milieu de la recherche, et un seul `bestmove` est émis).
- Comportement pré-existant conservé : `--bench` n'est reconnu que comme
  **premier** argument (`Argument(1) = "--bench"`), inchangé.

### 55.4 Tests

`BBChess.Protocol.Self_Tests.Run` (appelé depuis `--selftest`) teste les parsers
purs (`go` avec valeurs valides/malformées/absentes, `setoption`, `level`,
`time`) et le dispatch capturé (`uci`, `isready`, `position startpos|fen` avec
coups valides et invalides, FEN rejetée, `setoption`, `protover`, `ping`, ligne
vide, `quit`, coup nu). Aucun de ces tests ne démarre de recherche.

## 56. Découpage des self-tests et harnais pass/fail (P1.2)

`Self_Tests.Run` était une procédure de **823 lignes** enchaînant 116
vérifications : le premier échec (`raise Program_Error`) masquait tous les
suivants, et le programme sortait en erreur sans dire combien de tests passaient.

### 56.1 Découpage

`Run` ne fait plus qu'appeler dix-neuf procédures par domaine :
`Test_Board_Primitives`, `Test_Make_Unmake`, `Test_Perft`, `Test_Zobrist`,
`Test_Packed_Moves`, `Test_Fen_Validation`, `Test_Ep_Fen`, `Test_Ep_Arithmetic`,
`Test_Eval`, `Test_Search`, `Test_Time_Management`, `Test_Soft_Hard_Search`,
`Test_Repetition`, `Test_See`, `Test_Polyglot`, `Test_TT_Data`, `Test_Smp`,
`Test_Text_Handling`, `Test_Thread_Arguments`.

### 56.2 Harnais pass/fail

Nouveau paquet `BBChess.Test_Harness` : `Check` enregistre un succès ou un
échec, imprime `FAILED: <message>` pour un échec, et **ne s'arrête pas** — donc
le premier échec ne masque plus les suivants. `Run` affiche le bilan
(`126 checks passed, 0 failed`) et, si au moins un test échoue, positionne le
code de sortie à `Failure` : la CI échoue réellement au lieu de passer en
silence. La couverture est **exactement** conservée (les 116 vérifications,
dont les 2 `Program_Error` convertis en `Check`, comptent à l'identique).

### 56.3 Un bug de test révélé par le nouveau harnais

Le harnais a immédiatement mis au jour un défaut du **test** de protocole ajouté
en P1.1 : son dispatch `uci` activait la sortie UCI et son
`setoption Threads 3` changeait le nombre de threads **globaux**. Ces états
n'étant pas restaurés, les tests de recherche suivants s'exécutaient en
multi-thread et imprimaient des lignes `info`, rendant
`zero soft/hard search must match the fixed-depth node count` **non
déterministe** (1 ou 2 échecs selon le run). Correctif : le test restaure
`Set_UCI_Mode (False)`, `Set_Post (False)`, `Set_Threads (1)` et `Reset_Search`
avant de rendre la main. Résultat : 126/126, stable sur 6 exécutions
consécutives.

## 57. Allègement de `Negamax` (P1.3)

`Negamax` faisait **437 lignes**. La consigne demandait d'externaliser les blocs
d'élagage (null-move, futilité, razoring, LMP) en sous-programmes `Inline`.

### 57.1 Ce qui a été extrait

Les **décisions** d'élagage (et non les blocs eux-mêmes) sont devenues des
prédicats purs `Inline` au début de la fonction : `Can_Razor`,
`Can_Reverse_Futility`, `Can_Null_Move`, `Can_Late_Move_Prune`,
`Can_Futility_Prune`. Les blocs n'ont pas pu être déplacés tels quels car ils
contiennent des `return` et des `goto Next_Move` liés à la boucle de recherche
englobante ; un prédicat laisse le contrôle inchangé.

### 57.2 Résultat mesuré, et le contre-exemple instructif

Iso-comportement strict : nœuds `--bench 9/11/12` = 518 612 / 1 286 807 /
2 358 722, **identiques**.

Le bloc de **réduction de coup tardif (LMR)** a d'abord été extrait lui aussi
(`LMR_Reduction`). Mesure A/B entrelacée contre le binaire d'avant (15 paires,
`--bench 12`, médianes) : **+3,3 % de temps (+2,2 % sur le minimum)**, nœuds
pourtant identiques. Les prédicats sont bien inlinés (aucun symbole émis dans
le binaire), mais le déplacement perturbait l'allocation de registres de la
boucle de coups, qui est le cœur chaud de la fonction. Conformément à la
consigne (« si l'inlining ne se fait pas et que les nps régressent, reviens en
arrière »), le bloc LMR est **laissé inline dans `Negamax`**.

Après ce retour en arrière, A/B entrelacée (12 paires) : **delta médian
0,0 %, minimum −1,2 %** — parité, nœuds identiques. Les prédicats du prologue
de nœud (`Can_*`), eux, ne coûtent rien.

`--selftest` reste vert (126/126) dans les quatre modes, `debug` sans
avertissement.

## 58. Encapsulation des tables d'attaque (P1.4)

`bbchess-attacks.ads` exposait en clair des variables globales mutables
(`Knight_Attacks`, `King_Attacks`, `Pawn_Attacks`, `Between`, `Line`,
`Rook_Ray`, `Bishop_Ray`, `File_A_BB`, `File_H_BB`), sans partie `private` :
n'importe quel module pouvait les corrompre après `Init`.

### 58.1 Ce qui a changé

Les neuf tables sont désormais dans la partie **`private`** (`Knight_Table`,
`King_Table`, `Pawn_Table`, `Between_Table`, `Line_Table`, `Rook_Ray_Table`,
`Bishop_Ray_Table`, `File_A_Table`, `File_H_Table`). L'accès se fait par des
**accesseurs `Inline` portant le même nom** que les anciennes variables :
`Knight_Attacks (S)`, `Between (A, B)`, `File_A_BB`, etc. Les sites d'appel
(movegen, SEE, évaluation, pin mask) restent donc textuellement identiques.

### 58.2 Coût nul à -O3, vérifié

- Les accesseurs sont **entièrement inlinés** : `nm` sur le binaire release ne
  montre que les neuf **données** privées, aucun symbole de fonction
  d'accès.
- Iso-comportement : nœuds `--bench 9/11/12` = 518 612 / 1 286 807 / 2 358 722,
  **identiques**.
- Mesure A/B entrelacée (12 paires, `--bench 12`, contre le binaire précédent) :
  **delta médian −1,2 %** (dans le bruit, donc coût nul).
- `--selftest` vert (126/126) dans les quatre modes, `debug` sans
  avertissement.

### 58.3 Effet sur le `Type_Invariant` différé (P0.3)

Cette encapsulation ne privatise pas `Position_Type` (elle ne concerne que les
tables d'attaque), mais elle démontre que le motif « données privées + accesseurs
`Inline` » passe bien l'optimiseur sans coût. C'est le préalable technique du
chantier qui débloquera, pour `Position_Type`, le `Type_Invariant` laissé en
suspens en §54.3.

## 59. Fin du busy-wait de `Reclaim_Worker` (P2.1)

`Reclaim_Worker` attendait la terminaison effective d'une tâche de recherche
avec `while not Is_Terminated (...) loop delay 0.0; end loop;` : `delay 0.0`
n'est pas une attente mais un **tour de boucle actif**, qui garde un cœur à
100 % pendant la fenêtre de terminaison.

Le remplacement par une attente sur la barrière `Completion` n'est **pas
possible** : `Done.Wait_All` rend la main dès que chaque worker a exécuté son
dernier énoncé (`Done.Signal`), alors que `Is_Terminated` ne devient vrai
qu'une fois la comptabilité de terminaison du runtime achevée — un instant
**postérieur**, non observable via la barrière. La condition est donc
conservée, mais le délai passe à **1 ms** (`delay 0.001`), qui cède le
processeur au lieu de le brûler. Le test précède le délai et `Wait_All` a déjà
rendu la main : en pratique la tâche est terminée au premier test et aucun
délai n'est payé.

Vérifié : recherche à 8 threads, trois `go depth 8` enchaînés → trois
`bestmove`, aucune fuite ni blocage (le `--selftest` compte d'ailleurs un test
de régression SMP).

## 60. Journalisation des exceptions avalées (P2.2)

Deux `when others => null` masquaient toute exception : dans la tâche
`Searcher` (le worker de recherche Lazy SMP) et dans la tâche `UCI_Search_Task`.
Un crash de worker devenait un **ralentissement inexpliqué**.

Nouveau `BBChess.Search.Log_Worker_Exception`, qui écrit
`Exception_Information` sur la **sortie d'erreur standard** (jamais `stdout` :
le protocole UCI/XBoard doit rester propre), sous le **verrou console** déjà
partagé par `Locked_Put_Line`, donc sans entrelacement entre tâches.

- La tâche `Searcher` journalise puis garde son comportement : elle atteint
  toujours `Done.Signal` (sinon la barrière `Done.Wait_All` bloquerait à
  jamais).
- La tâche `UCI_Search_Task` journalise puis répond `bestmove 0000` : le
  protocole reste servi.
- Vérification par injection : une exception forcée dans le worker produit
  bien `warning: search worker exception: raised PROGRAM_ERROR : ...` sur
  `stderr`, tandis que `stdout` continue d'émettre `bestmove` normalement.

## 61. Contrôles de style (P2.3) et hypothèse mémoire x86-64 (P2.4)

### 61.1 `-gnatyy` : tentative puis **retrait** (correction d'une erreur)

La consigne demandait d'activer `-gnatyy` (contrôles de style GNAT :
indentation, espaces, casse, largeur des lignes…) **si le style est déjà
cohérent**. Il ne l'est pas : l'activation a produit **1 445 messages
`(style)`** dans **38 fichiers** — dont 1 033 « space required », 257 « this
line is too long », 134 « subprogram body has no previous spec » — et la CI,
qui compile `debug` avec `-cargs:ada -gnatwe` (tout avertissement devient une
erreur), est passée au **rouge**.

Deux erreurs distinctes, toutes deux corrigées :

1. **L'affirmation « zéro violation » était fausse.** La première vérification
   avait filtré `error|warning` ; les messages `(style) …` ne contiennent ni
   l'un ni l'autre et ont échappé au filtre. La mesure correcte (`grep
   '(style)'`) donne les 1 445 ci-dessus.
2. **Le suivi de la CI avait été interrompu** après P1.1 ; les échecs de P2.3,
   P2.5 et suivants n'ont pas été vus tout de suite.

`-gnatyy` est donc **retiré** de `babachess.gpr` : le mettre aurait exigé un
reformatage massif des 38 unités (coût élevé, risque de régression nps), hors
du périmètre « écarts résiduels » de la tâche. Le build `debug` revient à
`-gnat2012 -gnata -g -gnatwa -gnatVa`, et la CI recompile `debug` avec
`-gnatwe` **sans erreur**. Détail de l'incident : §64.

### 61.2 Hypothèse mémoire x86-64 (TT lock-free)

Le dépôt ne compte que **3 `pragma Atomic`** (`Data`, `Key_Xor`, `Num_Threads`),
**0 `Volatile`** et **aucune barrière mémoire explicite**. La TT lock-free
(entrée auto-vérifiante `Key_Xor xor Data = Key`) est néanmoins correcte — mais
**uniquement sur x86-64**, grâce au modèle **TSO** (Total Store Order) :

- un accès 64 bits aligné naturellement est **atomique** (pas de déchirure),
  ce qui fait fonctionner la clé auto-vérifiante ;
- les écritures d'un thread sont observées par les autres **dans l'ordre du
  programme** : un lecteur qui voit le `Data` d'un emplacement voit aussi le
  `Key_Xor` écrit avant lui, et la vérification par xor rejette tout couple
  non écrit ensemble.

Ce schéma **casserait sur un modèle faible** (ARM/AArch64, POWER) : le
compilateur ou le CPU pourrait réordonner les deux écritures indépendantes, et
un lecteur pourrait observer un couple `Data`/`Key_Xor` issus d'écritures
différentes qui vérifie quand même. Un portage sur une telle cible exigerait
des sémantiques release/acquire ou une barrière explicite. L'hypothèse est
documentée en commentaire au-dessus de `TT_Entry` (et ci-dessus), sans
modification du code de la TT.

## 62. Durcissement du parseur Polyglot (P2.5)

`Open_Book` (`bbchess-polyglot.adb`) lisait un `.bin` sans validation : taille
non multiple de 16, fichier tronqué, fichier vide ou lecture courte pouvaient
produire un livre corrompu sans message.

### 62.1 Validation et statuts

`Open_Book` renvoie désormais un **`Load_Status`** explicite au lieu d'un
booléen : `Loaded`, `File_Not_Found`, `Empty_File`, `Truncated`, `Bad_Size`,
`Read_Error`.

- La taille doit être un **multiple de 16** (taille d'une entrée Polyglot), au
  moins une entrée : un fichier vide, tronqué ou de taille invalide est
  **rejeté**, jamais parsé.
- Une **lecture courte** contredisant la taille validée est traitée comme
  `Read_Error`, et le livre à moitié lu est **libéré** (jamais conservé).
- `Status_Message` produit un message d'une ligne ; le paquet reste **sans
  I/O** et l'appelant décide de le rapporter.

### 62.2 Rejet propre et message clair

- Un `--book <f>` explicite ou un `setoption name BookFile` qui échoue affiche
  `info string book not found: ...` (ou `empty`/`truncated`/…). Pour que le
  message du `--book` ne soit pas perdu, l'application du livre a été déplacée
  **après** l'installation du writer dans `babachess.adb`.
- Le **sondage des emplacements conventionnels** (`Load_Default_Book`) reste
  **silencieux** : un candidat manquant est le cas normal.
- `Probe` revalide de toute façon chaque coup (`Decode` contre la position) :
  une entrée périmée est rejetée, jamais jouée.

### 62.3 Tests

Six cas ajoutés au `--selftest` (fichiers écrits dans un répertoire de travail
temporaire) : fichier absent, vide, 10 octets (tronqué), 40 octets (taille
invalide), entrée valide de 16 octets chargée, sonde d'une clé absente. Aucun
ne plante, aucun ne renvoie de coup illégal. `--selftest` passe de 126 à
**136 vérifications**, toutes vertes.

## 63. Décomposition de `Positional_Score` en termes nommés (P3.1)

`Positional_Score` (`bbchess-eval.adb`, 281 lignes) calculait tous les termes
positionnels en un seul bloc : impossible de les mesurer ou de les tuner
individuellement. La fonction est scindée en **six fonctions locales nommées**,
chacune autosuffisante :

| Terme | Contenu |
|---|---|
| `Bishop_Pair_Term` | bonus de la paire de fous |
| `Mobility_Term` | mobilité par pièce + menaces mineures sur majeures + fichiers ouverts/semi-ouverts + tour en 7ᵉ ; produit aussi les paramètres de sortie de danger du roi (consommés par `King_Safety`) |
| `Connected_Rooks_Term` | tours connectées |
| `Pawn_Structure_Term` | pions doublés / isolés / passés (protégés, extérieurs) |
| `Pawn_Threats_Term` | pions attaquant des pièces ennemies |
| `King_Activity_Term` | activité du roi en finale (remplace la PST orientée domicile) |

### 63.1 Iso-comportement strict

La somme des termes reproduit **exactement** l'arithmétique précédente
(l'addition entière est exacte à ces amplitudes, l'ordre est donc sans effet).
Vérifié :

- `--bench 9/11/12` = 518 612 / 1 286 807 / 2 358 722 nœuds, **identiques** ;
- évaluations `--eval-fens` sur 5 positions (dont un milieu de partie, un
  final de pions, Kiwipete) **identiques**, et **bit-à-bit identiques entre
  `debug` et `release`** ;
- symétrie `Static` toujours vérifiée par `--selftest` (136/136) ;
- A/B entrelacée (12 paires, `--bench 12`) : **delta médian 0,0 %, minimum
  −1,2 %** (parité).

La décomposition ne change pas la force ; elle rend chaque terme mesurable et
prépare tout tuning ultérieur terme par terme.

## 65. Bilan de la phase P3 (P3.2, P3.3, P3.4) — mesures contre hypothèses

La spécification de P3 supposait certains postes « rentables ». Le profil réel du
moteur (`perf record -F 6000` sur `--bench 12`, release) contredit plusieurs de
ces hypothèses. Ce qui suit est **mesuré**, pas supposé.

### 65.1 Coût réel de l'évaluation (profil `perf`)

| Symbole | % du temps total |
|---|---|
| `Negamax` | 37,9 % |
| `Positional_Score` (dont les termes ci-dessous) | 18,9 % |
| └ `Mobility_Term` | **11,35 %** |
| └ `Positional_Score` propre (paire de fous, tours connectées, activité du roi) | 4,09 % |
| └ `Pawn_Structure_Term` | **1,00 %** |
| └ `Pawn_Threats_Term` | 0,62 % |
| `Generate_Legal_Common` (movegen) | 16,3 % |
| `Static_Exchange_Value` | 4,1 % |
| `King_Safety` | 2,2 % |

### 65.2 P3.2 — table de hachage des pions : **non implémentée, sur mesure**

La spécification la présentait comme « le gain le moins cher ». **C'est faux pour
ce moteur** : `Pawn_Structure_Term` ne pèse que **1,00 %** du temps total. Une
table de hachage parfaite économiserait donc **au plus 1 %** de temps, et la
sonde + le calcul d'une clé de pions (qui devrait être maintenue séparément, la
clé Zobrist existante mêlant trait/roques/ep) coûterait une fraction comparable :
le gain net réaliste est **de l'ordre de 0 à +0,5 % de nps, voire négatif**.

- Le terme est déjà entièrement bitboard (propagation de portée, effondrement des
  fichiers par multiplication, ensembles d'attaques de pions en bloc) : il n'y a
  presque rien à mettre en cache.
- Une vérification indépendante par nps le confirme : en **court-circuitant
  entièrement le terme** (expérience jetable, non livrable car elle change
  l'arbre), les **knps restent identiques** (2 848 vs 2 831) — signature d'un
  travail par nœud négligeable.
- Un gain de nps < 1 % vaut ~0,3–0,5 Elo : **indétectable** par un SPRT de 300
  parties, et sous le seuil de résolution même à 1 000 parties. Ce n'est pas un
  levier de force.

Décision : **non implémentée**, documentée (le terme a déjà été optimisé là où
la spécification supposait qu'il ne l'était pas). Détail de conception écarté :
une table partagée lock-free façon TT (`Data`/`Key_Xor` atomiques, validation par
xor) est faisable, mais inutile vu le plafond.

### 65.3 P3.3 — tuning Texel : **déjà tenté et négatif (ne pas refaire)**

Le journal historique est sans ambiguïté :

- §21 : tuning Texel à **grande échelle** (100 000 positions humaines Lichess,
  `gen_dataset.py` + `tune.py`) — la MSE baisse mais le jeu de paramètres obtenu
  **perd ≈ 38 Elo** en SPRT 300 parties → **rejeté**. Conclusion consignée : « la
  MSE reste déconnectée de la force ; le tuning Texel n'est pas le bon levier ».
- §20 : SPSA (qui, lui, optimise le **résultat réel des parties**) sur l'éval —
  meilleur signal jamais vu (+20 ± 30 Elo, LOS 90 %) puis **SPRT étendu à 600
  parties : +0,6 Elo → bruit**. « Le tuning automatique d'éval est clos comme non
  concluant ».
- §44 : SPSA sur les constantes de recherche — **+2,1 ± 20,8 Elo → neutre**.
- AGENTS.md : « Eval tuning was a negative result — default parameters were kept
  on purpose ».

Deux méthodes indépendantes (Texel MSE, SPSA sur résultats) aboutissent au même
verdict : les valeurs par défaut sont un **optimum local** de cette évaluation.
Refaire un Texel large serait donc « refaire ce qui a déjà été tenté », ce que la
consigne interdit explicitement. Aucune tentative relancée.

### 65.4 P3.4 — sécurité du roi : close ; mobilité pondérée par phase : expérimentée

- **Sécurité du roi : close.** Trois tentatives, toutes **négatives** (§17.1,
  §17.2, puis re-vérification §17.4 avec le harnais corrigé : **−124 / −126 Elo**,
  LOS 0 %, mesure reproductible). Ne pas refaire.
- **Mobilité pondérée par phase : seule expérience légitime restante.** La
  mobilité était **plate** (`Both (Weight × N)`), donc identique en ouverture et
  en finale ; un tuner (SPSA/Texel) ne peut pas *inventer* une pente de phase, il
  ne peut que déplacer le poids unique. Rendre les poids **distincts par phase**
  est donc un changement **structurel** jamais tenté, et c'est le poste le plus
  chaud (11,35 %).

  Infrastructure ajoutée : paramètres `P_Mobility_{N,B,R,Q}_Eg` ; **défauts égaux
  aux poids d'ouverture**, donc **bit-identique** tant qu'aucun fichier de
  paramètres ne les change (même patron que D4 §43 : infrastructure durable,
  défauts bit-identiques). Vérifié iso-comportement : nœuds
  `--bench 9/11/12` identiques, évaluations `--eval-fens` identiques, A/B
  entrelacée à **0,0 %** médian, `--selftest` 136/136, `debug` sans
  avertissement.

  Le candidat testé (majeurs pondérés plus fort en finale : `P_MOBILITY_R_EG 3`,
  `P_MOBILITY_Q_EG 2`) est un vrai changement d'arbre (eval modifiée). Son SPRT
  est consigné ci-dessous.

## 64. Incident CI : `-gnatyy` et suivi interrompu (corrigé)

### 64.1 Les faits

Le commit P2.3 (`5db30fb`) a ajouté `-gnatyy` au mode `debug`. La CI a échoué
(`compilation phase failed`, code 4) sur `babachess.adb`, puis sur chaque push
suivant (P2.5, P2.6/P3.1), jusqu'à ce que l'échec soit remarqué et corrigé.

### 64.2 Les deux causes

1. **Mesure erronée du style.** La vérification de P2.3 filtrait la sortie de
   compilation sur `error|warning`. Les messages de style GNAT ont la forme
   `fichier:ligne:col: (style) …` et ne contiennent **ni** « error », **ni**
   « warning » : ils sont passés à travers le filtre. La mesure correcte
   (`grep '(style)'`) donne **1 445 messages dans 38 fichiers**. L'affirmation
   « zéro violation » de §61.1 était donc fausse.
2. **Suivi de la CI interrompu.** Après P1.1, les pushs n'ont plus été suivis
   par `gh run watch`. Les échecs ont donc persisté plusieurs commits.

### 64.3 Le correctif

- `-gnatyy` est **retiré** de `babachess.gpr` ; le mode `debug` retrouve ses
  commutateurs d'origine (`-gnatwa -gnatVa`).
- Le build exact de la CI a été rejoué localement
  (`gprbuild -P babachess.gpr -XMode=debug -cargs:ada -gnatwe`) : **code 0**.
- Le suivi de la CI par `gh run watch` est repris pour chaque push.

### 64.4 Leçon

Une vérification qui filtre sur `error|warning` **rate les messages `(style)`**
et, plus généralement, tout diagnostic dont le libellé diffère. Mesurer un
critère doit se faire sur le motif propre à ce critère (ici `(style)`), pas sur
un filtre supposé. Et un build « propre » localement ne vaut rien tant que la
**CI** n'a pas confirmé (le `-gnatwe` de la CI promeut des messages que le
build local, sans `-gnatwe`, laisse passer).
