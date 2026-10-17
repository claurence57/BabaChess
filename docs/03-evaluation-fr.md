# 3. Évaluation

L'évaluation note une position figée, sans anticiper de coups : « qui est mieux,
et de combien ? ». La recherche l'appelle à chaque feuille, donc sa qualité
oriente tout le jeu. Ce chapitre part du matériel et ajoute les ingrédients de
l'évaluation positionnelle : échelle, valeurs, tables pièce-case, phase, termes, échellisation
des nulles, symétrie, évaluation paresseuse et réglage automatique. BabaChess,
moteur bitboard en Ada 2012, sert d'exemple : évaluation faite à la main, sans
NNUE, réglée par Texel.

## 3.1 Du matériel au positionnel

L'évaluation la plus simple additionne la valeur des pièces de chaque camp et
soustrait : la différence est le score. Cela bat déjà un débutant. Mais à
matériel égal, un cavalier central vaut mieux qu'un cavalier au bord, des pions
liés mieux que des pions doublés, un roi abrité mieux qu'un roi exposé. Une
évaluation positionnelle ajoute donc des **termes** à la somme matérielle
(mobilité, structure de pions, sécurité du roi...), chacun captant une parcelle
de connaissance échiquéenne.

## 3.2 L'échelle en centipions

Un score se mesure en **centipions** (centipawns) : un pion vaut 100. Le signe
est conventionnel, positif quand les Blancs sont mieux ; +50 annonce un demi-pion
d'avantage. Les bornes de mat (`Infinity`, `Mate_Score`, `30_000` dans BabaChess)
encadrent les valeurs ordinaires : la recherche distingue ainsi un mat d'une
position simplement gagnante.

## 3.3 Valeur des pièces

La table classique sert de socle : pion 100, cavalier 320, fou 330, tour 500,
dame 900, roi 0. Le fou vaut un peu plus que le cavalier, la tour un peu moins de
cinq pions. Le roi vaut zéro car il ne peut être capturé ; sa valeur se joue dans
la sécurité. Ces nombres sont des conventions que le réglage automatique ajuste.

## 3.4 Tables pièce-case

Une **table pièce-case** (PST) est un tableau de 8×8 donnant, par pièce et par
case, un bonus ou un malus : cavalier pénalisé sur les bords, fou attiré par les
grandes diagonales, tour récompensée sur la 7ᵉ, roi poussé au centre en finale.
Écrite du point de vue d'un camp, lignes allant de la rangée arrière (0) au camp
adverse (7), elle se lit par `Rank_Of (case)` pour les Blancs et
`7 - Rank_Of (case)` pour les Noirs : **une seule table sert les deux camps**,
sans duplication. BabaChess les nomme `Pawn_PST`, `Knight_PST`, `Bishop_PST`,
`Rook_PST`, `Queen_PST`, `King_PST` et `King_End_PST`.

## 3.5 Phase de jeu et évaluation tapered

Tous les termes ne pèsent pas pareil selon l'avancement : une tour sur colonne
ouverte est utile au milieu de jeu et décisive en finale, un roi central y est
dangereux au milieu de jeu mais excellent en finale. L'**évaluation tapered** évalue donc chaque terme
**deux fois**, ouverture et finale, puis **interpole** selon la phase. La phase
vient du matériel restant (4 par cavalier, 4 par fou, 9 par tour, 16 par dame,
plafonné à 100) : 100 au départ, 0 dans une finale de rois et pions.

BabaChess porte la paire `Opening` / `End_Game` dans un `Tapered_Score_Type` et
l'interpole par `Blend` : paire de fous de 20 à 45, tour sur la 7ᵉ de 15 à 35,
pions passés à bonus croissant avec la rangée, `King_End_PST` qui corrige le roi
en finale.

## 3.6 Les termes positionnels

Chaque terme se calcule **par couleur** puis les deux scores se soustraient.
Écrire le code avec une couleur générique, sans branches « Blanc » / « Noir », est
la clé de la symétrie (section 3.8).

### 3.6.1 Structure de pions

Elle se détecte en bitboard, sans boucle par pion :

- **doublés** : plus d'un pion sur une colonne, pénalité par pion excédentaire ;
- **isolés** : aucun pion ami sur les colonnes voisines, pénalité par pion ;
- **passés** : aucun pion ennemi devant, bonus croissant avec la rangée ;
- **arrière** : un pion retardé, souvent sur une colonne semi-ouverte.

BabaChess détecte les passés avec `Front_Blockers` : colonnes élargies,
propagation rangée par rangée, sept décalages fixes.

### 3.6.2 Pièces : mobilité, paire de fous, tours, menaces

La **mobilité** compte les cases atteignables : pour chaque cavalier, fou, tour
et dame, on engendre les attaques selon l'occupation et on compte les cases
libres, `Popcount (Piece_Attacks and Free)`. Le poids dépend de la pièce, le
cavalier et le fou étant les plus sensibles à leur liberté. La **paire de fous**
ajoute un bonus, plus fort en finale. Les **tours** aiment la 7ᵉ rangée (renforcée
si le roi adverse est resté en arrière), les colonnes ouvertes (aucun pion) ou
semi-ouvertes (aucun pion ami), et se connectent quand elles se défendent sur la
même ligne. Les **menaces** récompensent les attaques sur des pièces non
défendues : pièce ennemie attaquée par un pion ami, ou cavalier / fou attaquant
une tour ou une dame. Les masques de colonne (`File_Mask`) évitent tout parcours
par pion ; BabaChess calcule la zone d'attaque une fois par évaluation.

### 3.6.3 Sécurité du roi

La sécurité du roi repère les attaquants autour de lui et les faiblesses de son
abri : bouclier de pions, colonnes ouvertes, avancée adverse (pion-storm). Le
danger est **non linéaire**, une attaque coordonnée pesant plus que la somme des
pièces. C'est le terme le plus délicat : BabaChess le limite à l'ouverture et au
milieu de jeu (`Phase >= King_Safety_Min_Phase`) et le garde gelé.

## 3.7 Échellisation des positions nulles

Une position gagnante sur le papier peut être nulle en pratique : pièce de plus
sans aucun pion, ou fous de couleurs opposées. Garder tout le bonus matériel y
pousse la recherche à se battre pour un gain inexistant. L'**échellisation des
nulles** multiplie alors le score par un facteur inférieur à un. BabaChess calcule
un `Scale_Factor` sur 64 : sans pion et avec au plus une pièce mineure d'avance,
0, 4 ou 14 ; fous de couleurs opposées seuls, `Scale_OCB`.

## 3.8 Symétrie de l'évaluation

L'évaluation doit être **symétrique** : renverser le plateau en échangeant les
couleurs doit changer le signe du score, sinon un biais favoriserait un camp.
Trois règles y veillent : les PST lisent la rangée dans le repère de la couleur ;
les termes se calculent par couleur générique puis se soustraient ; `Static`
n'ajoute rien qui dépende du trait. La propriété s'écrit
`Static (M) = -Static (P)` quand `M` miroite `P`. Comme `Evaluate` ajoute un
**bonus de tempo**, la symétrie exacte porte sur `Static`. On la teste par des
invariants (`Static` du départ = 0, `Evaluate` = tempo, miroir opposé), ce que
fait `Check_Symmetry` sur des FEN variés. Toute nouvelle évaluation doit rester
symétrique : c'est la règle d'or.

## 3.9 Évaluation paresseuse

Calculer tous les termes à chaque feuille coûte cher. L'**évaluation paresseuse**
(*lazy evaluation*) exploite le raisonnement par bornes : si le total matériel
plus tables dépasse déjà la borne courante d'une marge suffisante, le détail ne
change pas la décision et on renvoie ce total approché. BabaChess ne la pratique
pas : tous ses termes sont calculés, mais sa partie matériel plus PST est
**incrémentale** (`Make_Move` / `Unmake_Move`).

## 3.10 Réglage automatique (Texel)

Le **réglage automatique** remplace l'intuition par une optimisation sur données.
La méthode Texel minimise l'écart entre le résultat réel des parties et la sortie
de l'évaluation : positions étiquetées (`FEN;résultat`), score passé par une
sigmoïde, descente de coordonnées sur l'erreur quadratique moyenne. C'est une
boucle fermée : chaque candidat est mesuré par le binaire via
`--eval-fens --params`, donc l'évaluation réglée est celle qui joue.

BabaChess fournit `scripts/texel_extract.py` (jeu de positions calmes issu
d'auto-jeu) et `scripts/texel.py` (réglage des scalaires et des tables). Leçon du
projet : une erreur d'entraînement plus basse ne garantit pas plus de force, et
un jeu ne se garde qu'après un SPRT. Piste complémentaire : SPSA, avec le même
binaire.

## 3.11 BabaChess comme exemple

L'évaluation vit dans `BBChess.Eval` (`src/bbchess-eval.ads` / `.adb`) : matériel
plus PST incrémental, phase, termes par couleur, soustraction, `Blend`. `Static`
renvoie le score blanc-positif et reste symétrique ; `Evaluate` l'oriente vers le
trait et ajoute le tempo. Les paramètres scalaires sont dans une table `Params`,
exposée par `--dump-params` et chargeable par `--params`, ce qui rend le réglage
possible sans reconstruire le moteur. L'évaluation reste **faite à la main, sans
NNUE** ; les réseaux sont une autre voie, évoquée plus loin.

## Voir aussi

- `src/doc/evaluation-fr.md` : référence technique (phase, termes, paramètres,
  résultats négatifs).
- `src/doc/bitboards-fr.md` : représentation qui rend naturels les termes de pions et
  de mobilité.
- `src/bbchess-eval.adb` : `Positional_Score`, `Game_Phase`, `Blend`,
  `King_Safety`, `Scale_Factor`.
- `scripts/texel_extract.py`, `scripts/texel.py` : données et réglage Texel.
- Chapitres voisins : `02-board-and-movegen-fr.md`, `04-search-fr.md`.
