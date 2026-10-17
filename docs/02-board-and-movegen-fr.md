# 2. Représentation du plateau et génération de coups

Un moteur d'échecs répond sans cesse à deux questions : « où sont les pièces ? » et « quels
coups sont légaux ? ». La représentation de l'échiquier décide donc de beaucoup, de la
vitesse de recherche à la simplicité du code. Ce chapitre couvre les deux grandes familles
de représentation, la construction des attaques, la génération des coups et leur validation
par perft, avec BabaChess comme exemple concret.

## 2.1 Mailbox ou bitboards

La représentation **mailbox** décrit l'échiquier comme un tableau de 64 cases, chacune
contenant au plus une pièce. Déplacer une pièce, c'est écrire une valeur dans une case :
simple, mais lent, car parcourir les rayons d'une tour se fait case par case.

La représentation **bitboard** remplace le tableau par des **entiers de 64 bits**, un bit
par case. Les opérations d'ensemble (cases libres, occupation d'une couleur, cibles)
deviennent de simples `or`, `and`, `not`, appliqués aux 64 cases d'un coup. C'est l'approche
de BabaChess, où `Bitboard` est un type modulaire : `type Bitboard is mod 2 ** 64;` (voir
`src/bbchess-board.ads`).

### Indexation des cases

Une seule convention, appliquée partout :

- l'index d'une case est `Rang * 8 + Colonne` ;
- `File 0` = colonne A, `Rank 0` = rangée 1 (la base des Blancs) ;
- `bit 0` = a1, `bit 63` = h8 ;
- augmenter l'index va vers le nord : `+8` par rang, `+1` par colonne.

En Ada, `File_Of (S) = S mod 8` et `Rank_Of (S) = S / 8`. La convention a1 en bit de poids
faible est celle des bitboards modernes ; elle rend les décalages massifs des pions
particulièrement commodes (section 2.4).

### Encodage des pièces

Une pièce est un petit type énuméré, `Piece_Type`, qui range les douze pièces concrètes.
L'astuce est l'**ordre** : les six pièces blanches (`White_Pawn .. White_King`) puis les six
noires. Couleur et type se déduisent alors par arithmétique modulaire, sans table :
`Color (P)` compare la position à 6, `Kind (P)` prend la position modulo 6, et
`Make (Couleur, Type)` fait l'inverse (voir `src/bbchess-pieces.ads`).

## 2.2 Charger une position : FEN et état incrémental

Le point d'entrée standard est le **FEN** (Forsyth-Edwards Notation) : placement des pièces,
trait, droits de roque, case en passant, compteurs de demi-coups et de coups.
`src/bbchess-fen.adb` le décompose champ par champ.

Le placement se lit de la rangée 8 vers la rangée 1, chaque chiffre comptant des cases
vides. Le parseur est **strict** : une rangée qui ne fait pas exactement huit cases, un `/`
manquant ou une neuvième rangée sont rejetés, car un décalage silencieux corromprait tout le
reste. Avant de rendre la position, il vérifie des invariants : exactement un roi par camp,
pas de pion sur la première ni la huitième rangée, matériel cohérent, et surtout le camp qui
n'a pas le trait ne doit pas être en échec (un roi capturable signalerait un FEN illégal).

Au-delà des cases, une position porte un **état incrémental** entretenu par
`Put_Piece` / `Remove_Piece` / `Move_Piece` :

- `All_Occ` (occupation totale) et `Color_Occ` (par couleur), mis à jour bit à bit à chaque
  mutation, jamais recalculés par balayage ;
- la table `Squares`, qui donne la pièce d'une case en O(1) ;
- `Key`, la clé de **Zobrist** utilisée par la table de transposition
  (`src/bbchess-hash.ads`) ;
- `Material`, la somme matérielle avec les tables de position.

La table `Squares` n'est valide que sur une case occupée : c'est un invariant à respecter à
la lecture.

## 2.3 Attaques : sauteurs et glisseurs

Générer un coup, c'est surtout calculer les attaques. On sépare deux familles.

### Les sauteurs : cavalier, roi, pions

Les attaques d'un **sauteur** ne dépendent pas de l'occupation : un cavalier attaque
toujours les mêmes huit cases depuis une case donnée. Elles sont donc précalculées une fois
à l'élaboration, dans `src/bbchess-attacks.adb`. Le corps part de tableaux de deltas
`(dColonne, dRang)` et applique `Build_Leaper` : pour chaque delta, on vérifie que la case
reste sur l'échiquier, puis on pose le bit correspondant.

Les pions sont traités à part, car un pion blanc attaque en montant et un pion noir en
descendant : deux tables distinctes, indexées par couleur. Conséquence utile : pour savoir
si une case est attaquée par un pion, on lit la table de la couleur **opposée**, la relation
s'utilise à l'envers.

### Les glisseurs : fou, tour, dame

Fou, tour et dame voient leurs attaques **dépendre de l'occupation** : un bloqueur arrête le
rayon. La solution usuelle est un **indexage** : on comprime l'occupation pertinente en un
petit entier, qui indexe une table précalculée. BabaChess utilise `PEXT` (BMI2), qui extrait
les bits d'occupation tombant dans un masque et les compacte. Comme `PEXT` est une
**bijection** entre les sous-ensembles du masque et les index `0 .. 2^n - 1`, il n'y a aucune
collision, donc aucun « magic number » à chercher : contrairement aux magic bitboards, la
table se remplit directement. La tour demande jusqu'à 12 bits d'index (4095 entrées), le fou
jusqu'à 9 (511). La dame n'a pas de table propre : `Queen_Attacks` vaut le `or` des attaques
de tour et de fou.

Deux tables carrées complètent l'ensemble, calculées depuis les attaques sur plateau vide :
`Between (A, B)` (cases strictement entre A et B) et `Line (A, B)` (ligne complète qui les
traverse). Elles servent à la détection d'échec et aux épingles. En mode `portable`, `PEXT`
reçoit un repli logiciel dans le shim C `src/bbchess-bits.c`, si bien que la génération de
coups ne connaît pas le mode de compilation.

## 2.4 Générer les coups : pseudo-légal, puis légal

La stratégie de BabaChess est « correction d'abord » : `Generate_Pseudo_Moves` produit tous
les coups qui respectent le déplacement des pièces, puis `Generate_Legal_Common` élimine ceux
qui laisseraient le roi en échec (voir `src/bbchess-movegen.adb`).

### Pions : décalages massifs

Les poussées et captures de pions sont calculées pour **tous les pions à la fois**, par
décalage de bitboard. Le rang occupant les bits de poids fort, avancer d'un rang revient à
multiplier par 256 (et reculer à diviser). Des masques de colonne (`File_A_BB`, `File_H_BB`)
évitent les captures qui enrouleraient d'un bord à l'autre. Les quatre cases de promotion
sortent par `Emit_Promotions`, qui émet dame, tour, fou puis cavalier.

Pour les autres pièces, on itère leurs bits puis on retire les cases amies :
`Bishop_Attacks (From, Occ) and not Own`, et de même pour tour, dame, cavalier et roi. Le
modificateur « tactique » ne garde que les cases ennemies, pour la quiescence.

### Filtre de légalité

Le filtre évite un `Make_Move` / `Unmake_Move` systématique en travaillant sur des masques :

1. `Attackers_To` énumère les pièces ennemies attaquant le roi : c'est le bitboard
   `Checkers`.
2. En **échec simple**, `Check_Mask` vaut le bit du donneur plus `Between (roi, donneur)` :
   il faut capturer ou s'interposer. En **échec double**, `Check_Mask = 0` : seul le roi peut
   bouger.
3. `Pin_Mask` calcule les pièces **absolument épinglées** : une pièce est épinglée quand elle
   est l'unique bloqueur entre son roi et un glisseur ennemi de direction compatible.
4. Un coup non-roi n'est gardé que s'il tombe dans `Check_Mask` et, si la pièce est épinglée,
   s'il reste sur `Line (roi, depart)`.
5. Le roi ne peut pas aller sur une case attaquée ; le test retire le roi de l'occupation,
   pour compter les attaques découvertes.
6. La **prise en passant** passe par un make/unmake complet, car elle peut découvrir une
   attaque sur la rangée.

Quand il n'y a ni échec ni pièce épinglée, tous les coups non-roi sont légaux d'emblée :
c'est un chemin rapide qui évite le filtre.

## 2.5 Coups spéciaux

Trois règles échappent au schéma « départ vers arrivée ».

- **Roque** : ajouté après les coups de roi, uniquement si les cases intermédiaires sont
  libres et non attaquées. Petit et grand roque sont deux drapeaux distincts.
- **Prise en passant** : la case cible est vide, donc absente des captures massives ; on
  retrouve les pions attaquants par la table de pions de couleur opposée.
- **Promotion** : un même déplacement engendre quatre coups, un par pièce de promotion.

Un coup est un petit enregistrement `Move_Type` (départ, arrivée, pièce, promotion, drapeau),
avec une forme compacte 32 bits pour la table de transposition. `Make_Move` renvoie un
`Undo_Info` qui permet à `Unmake_Move` de restaurer exactement l'état précédent : la position
reste une simple valeur copiable, ce qui simplifie perft, recherche et FEN. Voir
`src/bbchess-moves.ads`.

## 2.6 Perft : la vérité terrain

Comment savoir si un générateur de coups est correct ? On compte les nœuds d'un arbre de
coups légaux à profondeur fixe : c'est le **perft**. `Nodes` (`src/bbchess-perft.adb`) est
récursif : profondeur 0 renvoie 1, profondeur 1 renvoie directement le nombre de coups, sinon
il énumère les coups, fait `Make_Move`, descend en `Depth - 1`, puis `Unmake_Move`.

Le perft exerce exactement les briques de ce chapitre : tables d'attaques, filtre de
légalité, coups spéciaux, make/unmake. Si un rayon glissant saute un bloqueur, si un masque
de colonne est faux ou si une épingle est oubliée, le compte dévie. On le compare à des
valeurs connues :

| Position | Profondeur | Attendu |
|---|---|---|
| Initiale | 1 à 5 | 20, 400, 8 902, 197 281, 4 865 609 |
| Roque | 1 à 3 | 48, 2 039, 97 862 |
| En passant | 1 à 3 | 14, 191, 2 812 |
| Promotions | 1 à 2 | 44, 1 486 |

Règle d'or : tout changement de génération de coups doit garder `--selftest` vert et les
comptes de perft **inchangés**.

## Voir aussi

- `src/doc/bitboards-fr.md` : la description technique détaillée de la représentation et des
  attaques.
- Code : `src/bbchess-board.ads` / `.adb`, `src/bbchess-attacks.adb`,
  `src/bbchess-movegen.adb`, `src/bbchess-moves.ads` / `.adb`, `src/bbchess-perft.adb`,
  `src/bbchess-fen.adb`, `src/bbchess-hash.ads`.
- Sommaire du guide : `README-fr.md`. Chapitres voisins : `01-introduction-fr.md`,
  `03-evaluation-fr.md`, `04-search-fr.md`, `05-opening-book-fr.md`,
  `06-endgame-tablebases-fr.md`, `07-testing-fr.md`, `08-roadmap-and-limits-fr.md`.
- `src/doc/recherche-fr.md` et `src/doc/outils-et-tests-fr.md`.
