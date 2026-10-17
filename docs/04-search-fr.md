# 4. La recherche

Évaluer la position courante ne suffit pas : un moteur doit anticiper la réponse
adverse. La recherche explore l'arbre des coups, pèse les répliques et renvoie le
coup dont la ligne mène à la meilleure position. BabaChess l'implémente dans
`BBChess.Search` (`src/bbchess-search.adb`), avec `BBChess.See`
(`src/bbchess-see.adb`) pour la quiescence : une **négamax alpha-bêta** resserrée
par l'ordonnancement, la table de transposition et une famille d'élagages. Ce
chapitre décrit les idées ; `src/doc/recherche-fr.md` garde le détail des choix.

## 4.1 L'arbre de jeu et la négamax

La recherche modélise la partie comme un arbre : chaque nœud est une position,
chaque arête un coup légal, la profondeur se compte en demi-coups. Aux feuilles,
une évaluation statique estime la position ; au-dessus, chaque camp choisit la
suite qui lui est la plus favorable. **Minimax** alterne ainsi un maximum (mes
coups) et un minimum (les tiens), et la **négamax** le simplifie : si l'on score
toujours du point de vue du trait, la valeur d'un nœud est le maximum, sur tous
les coups légaux, de l'**opposé** de la valeur de l'enfant :

    valeur(position) = max( -valeur(enfant) )   pour chaque coup jouable

Un score élevé est donc toujours bon *pour celui qui doit jouer*. Les mats sont
décalés par le nombre de demi-coups pour préférer le plus rapide, un nœud sans
coup légal renvoie mat ou pat, et les nulles forcées (cinquante coups, matériel
insuffisant, répétition) sont traitées avant la table de transposition. Dans
BabaChess, `Negamax` bascule vers `Quiescence` à profondeur nulle.

## 4.2 Alpha-bêta et les bornes de la fenêtre

Explorer tout l'arbre est impossible : le nombre de nœuds croît de façon
exponentielle. L'**alpha-bêta** ne calcule pas une meilleure valeur, il évite du
travail. Chaque nœud reçoit une fenêtre `[Alpha, Beta]` :

- **Alpha** est la meilleure valeur déjà garantie au trait plus haut. En dessous,
  le nœud n'apporte rien : c'est un **fail low**.
- **Beta** est la borne que l'adversaire ne laissera pas dépasser. L'atteindre ou
  la dépasser est un **fail high** : la branche peut être coupée sans être finie.

Une branche qui ne peut pas changer le choix de la racine est donc abandonnée.
Dans le meilleur cas, alpha-bêta visite environ la racine carrée des nœuds de la
minimax, si le bon coup est examiné en premier ; au pire, il retombe sur la
minimax complète. Toute la force de l'algorithme tient à l'**ordre** des coups,
d'où la place démesurée de l'ordonnancement. BabaChess applique cette fenêtre à
la racine (`Root_Search`) comme aux nœuds internes (`Negamax`).

## 4.3 Ordonnancement des coups : le multiplicateur de force

Alpha-bêta est exact, mais sa vitesse dépend entièrement de l'ordonnancement :
mieux ordonner ne rend pas la recherche plus juste, elle la rend bien plus rapide
à profondeur égale, donc plus profonde à temps égal. Les heuristiques sont
réessayées dans cet ordre :

- **Coup de la table de transposition** : le meilleur coup déjà trouvé pour cette
  position. C'est le meilleur prédicteur qui existe.
- **Promotions**, puis **captures** classées par **MVV-LVA** (*Most Valuable
  Victim, Least Valuable Attacker*) : la pièce la plus chère prise par la moins
  chère. Une capture perdante au sens de l'échange statique passe après les coups
  tranquilles.
- **Killers** : deux coups tranquilles ayant déjà provoqué une coupure bêta au
  même demi-coup ailleurs.
- **Counter-move** : la réplique qui a réfuté le coup précédent de l'adversaire.
- **History et continuation history** : les coups tranquilles restants, classés
  par un score mémorisé par (pièce, case) ou (coup précédent, coup courant). Un
  coup qui a coupé gagne un bonus, un coup stérile reçoit un malus.

Ces tables apprennent en cours de recherche et se vieillissent (history halvée à
chaque itération). C'est un cercle vertueux : mieux ordonner produit plus de
coupures, donc plus de profondeur, donc de meilleures entrées de table. Tout cela
vit dans `Order`.

## 4.4 Approfondissement itératif et fenêtres d'aspiration

`Iterative_Search` ne cherche pas directement à profondeur maximale : il part de
la profondeur 1, puis 2, 3, et ainsi de suite. Chaque itération complète fournit
le meilleur coup, qui sert d'indice d'ordonnancement à la suivante, et le moteur
dispose toujours d'une réponse valide (la dernière itération terminée) même s'il
est interrompu.

On resserre ensuite la fenêtre : les **fenêtres d'aspiration** encadrent le score
précédent d'une petite marge (BabaChess : 40 centipions). Si le résultat tombe
dans la fenêtre, tant mieux ; sinon on n'élargit que la borne franchie et on
relance, en doublant la marge à chaque échec jusqu'à revenir à la fenêtre pleine.
Une itération s'arrête aussi plus tôt sur un mat ou un résultat de tablebase. La
recherche est interruptible : elle teste l'échéance tous les 1024 nœuds environ
et conserve la dernière itération complète.

## 4.5 Recherche de la variation principale (PVS)

La **PVS** (Principal Variation Search, ou scout) suppose que le premier coup,
le mieux ordonné, est le meilleur :

1. Le premier coup est cherché en **fenêtre pleine** `[-Beta, -Alpha]`.
2. Chaque coup suivant est d'abord cherché en **fenêtre nulle**
   `[-Alpha - 1, -Alpha]`, plus sévère et donc moins chère. S'il reste sous Alpha,
   on passe au suivant ; s'il le dépasse, il est **re-recherché en fenêtre
   pleine** pour obtenir son vrai score.

Le raisonnement est « présumé coupable, sauf preuve du contraire ». La méthode
n'est correcte que si le premier coup est vraiment le meilleur la plupart du
temps, ce qui ramène à l'ordonnancement. `Root_Search` applique la même stratégie
à la racine.

## 4.6 Table de transposition

Beaucoup de chemins mènent à la même position (e4 puis Cf3, ou Cf3 puis e4). La
**table de transposition** mémorise le résultat d'une position déjà rencontrée,
indexée par sa **clé de Zobrist** (condensé 64 bits maintenu de façon
incrémentale, voir `src/doc/bitboards-fr.md`), et évite de la recalculer.

Chaque entrée contient la clé complète, la profondeur restante, la **borne** du
résultat (`Exact`, `Lower_Bound` ou `Upper_Bound`), le score (mats normalisés par
le demi-coup), le meilleur coup et un âge. Le **remplacement** est un vrai choix
de conception : BabaChess utilise des compartiments à deux voies, garde l'entrée
la plus profonde et remplace d'abord les entrées périmées grâce à un compteur de
génération (*aging*). Le cutoff n'est appliqué que si l'entrée est au moins aussi
profonde que la recherche, mais le coup mémorisé est extrait même sans cutoff,
car il sert alors à l'ordonnancement.

## 4.7 Élagages et réductions aux faibles profondeurs

L'ordonnancement réduit l'arbre ; les élagages le coupent : juger qu'une branche
ne peut pas modifier le résultat et ne pas la chercher, ou la chercher moins
profond. Toutes ces techniques vérifient d'abord qu'on n'est **ni en échec ni
dans une position de mat**.

- **Null move** : passer son tour et chercher à profondeur réduite ; si même sans
  jouer on dépasse Beta, la coupure s'impose. Interdit en finale de pions, où le
  zugzwang rend le « passe » trompeur.
- **Reverse futility** : si l'évaluation statique atteint déjà Beta avec une marge
  dépendant de la profondeur, le nœud est renvoyé tel quel.
- **Futility** : un coup tranquille dont l'évaluation plus une marge ne peut pas
  rejoindre Alpha est sauté.
- **Razoring** : si l'évaluation statique est très en dessous d'Alpha, on vérifie
  par une quiescence et on renvoie si elle ne remonte pas jusqu'à Alpha.
- **Late move pruning (LMP)** : les coups tranquilles tardifs (au-delà de
  `4 + profondeur²`) ne sont pas cherchés ; ordonnés en dernier, ils n'améliorent
  presque jamais la fenêtre.
- **Late move reduction (LMR)** : un coup tranquille tardif est cherché à
  profondeur réduite, selon une formule logarithmique
  (`0,75 + ln(profondeur) × ln(rang) / 2,25`). On réduit moins sur la variation
  principale, plus dans un nœud à fenêtre nulle ; killers et coups donnant échec
  ne sont jamais réduits. Tout fail-high est re-vérifié à profondeur pleine, car
  la réduction peut créer une fausse coupure.

## 4.8 Extensions et élagage de distance de mat

À l'inverse, une **extension** approfondit une branche jugée importante. BabaChess
n'étend qu'un cas : un nœud où le trait est **en échec** cherche ses évasions un
demi-coup plus profond, car elles sont forcées et une séquence d'échecs ne doit
pas être tronquée par l'horizon. L'extension est bornée par le demi-coup.

L'**élagage de distance de mat** agit sur les bornes : aucun nœud ne peut valoir
mieux qu'un mat trouvé au demi-coup courant, ni pire qu'un mat subi tout de
suite. On borne donc Alpha et Beta par `-Mate_Score + Ply` et
`Mate_Score - Ply - 1`, et on coupe si les bornes se croisent.

## 4.9 Recherche de quiescence

Au bord de l'horizon, évaluer sèchement est dangereux : la position peut être au
milieu d'une série d'échanges, et l'évaluation statique n'en voit pas la fin. La
**quiescence** prolonge la recherche en ne cherchant que les coups **tactiques**
(captures et promotions) jusqu'à ce que la position se calme.

Hors échec, on évalue la position (**stand pat**) : si elle atteint Beta, on
coupe, si elle dépasse Alpha, on l'adopte. En échec, le stand pat est illégal et
toutes les évasions sont cherchées. L'**élagage de delta** saute une capture dont
la victime plus une marge n'atteint pas Alpha, et l'**élagage SEE** saute une
capture dont l'échange statique est perdant.

Le **SEE** (Static Exchange Evaluation) vit dans `BBChess.See` : il rejoue la
séquence de captures sur une case, choisit l'attaquant le moins cher en excluant
les pièces clouées, n'admet le roi qu'en dernier et laisse chaque camp renoncer à
reprendre. La valeur obtenue sert à la quiescence comme à l'ordonnancement.

## 4.10 Le compromis de la profondeur sélective

Tous les élagages et réductions échangent de l'exactitude contre de la profondeur.
Chaque coupure risque de manquer une tactique qui aurait renversé l'évaluation ;
en échange, l'arbre rétrécit et le moteur voit plus loin. Trop timide, l'élagage
ne gagne presque rien ; trop agressif, il égare la recherche. La bonne question
n'est pas « est-ce rigoureux » mais « est-ce que cela gagne des parties ».

BabaChess applique cette discipline : toute modification doit garder `--selftest`
vert, laisser `--bench` stable, puis passer une campagne SPRT de plusieurs
centaines de parties. Plusieurs techniques classiques ont été essayées puis
retirées après mesure neutre ou négative (extensions singulières, extension de
tout coup donnant échec, recherche itérative interne, échecs tranquilles en
quiescence). Le résultat est un ensemble de techniques éprouvées en match,
ajustables via `--params`.

## Voir aussi

- `src/doc/recherche-fr.md` : la documentation de référence de la recherche.
- Code : `src/bbchess-search.adb` et `src/bbchess-search.ads` (négamax, PVS,
  ordonnancement, élagages, Lazy SMP), `src/bbchess-see.adb` (échange statique).
- `src/doc/bitboards-fr.md` : clé de Zobrist, base de la table de transposition.
- `src/doc/evaluation-fr.md` : l'évaluation appelée aux feuilles.
- `src/doc/finales-fr.md` : le sondage WDL Syzygy, qui court-circuite la recherche.
- `src/doc/outils-et-tests-fr.md` : `--selftest`, `--bench`, `--params`, SPRT/SPSA.
- `src/doc/README-fr.md` : l'index de la documentation technique.
- Les autres chapitres du guide sont dans le dossier `docs/`.
