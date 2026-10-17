# 8. Feuille de route et limites

Construire un moteur d'échecs n'est pas un seul problème, c'est une échelle.
Chaque barreau ajoute de la force et chacun est plus dur que le précédent. Ce
chapitre ordonne les leviers par retour sur investissement, explique pourquoi les
gains diminuent, décrit le plafond que les moteurs artisanaux ont atteint, et
montre pourquoi NNUE l'a déplacé. Il se termine par une liste et par BabaChess
comme exemple concret.

## 8.1 L'ordre des efforts

Le parcours d'un moteur naïf vers un moteur fort suit un ordre stable : une étape
ne vaut que lorsque la précédente est solide.

| Ordre | Levier | Ce qu'il apporte |
|---|---|---|
| 1 | Correction (perft, self-tests) | le moteur joue aux échecs légalement, tout simplement |
| 2 | Vitesse (nœuds par seconde) | plus de profondeur pour le même temps |
| 3 | Ordonnancement des coups | un arbre plus petit pour la même profondeur |
| 4 | Agressivité de la recherche (élagages, réductions, extensions) | une recherche effective plus profonde |
| 5 | Connaissance de l'évaluation | un meilleur jugement aux feuilles |
| 6 | Réglage | les dernières gouttes de ce que l'on possède |

**La correction d'abord, la vitesse ensuite.** Une recherche rapide sur un
générateur de coups cassé ne vaut rien, donc on fait confiance au générateur en
comptant (perft 1 à 5, self-tests), avec des tests verts et une évaluation
symétrique (chapitre 7). La force croît alors avec la profondeur et la profondeur
avec la vitesse : doubler les nœuds par seconde vaut à peu près un demi-pli, donc
les bitboards et un chemin chaud profilé passent avant les idées astucieuses
(chapitres 2 et 4).

**L'ordonnancement en troisième, l'agressivité en quatrième.** Alpha-bêta veut le
bon coup en premier, donc coup de hash, MVV-LVA, killers, history et counter-move
réduisent l'arbre gratuitement. Puis null move, réductions, futility, razoring et
LMP achètent de la profondeur en élaguant ce qui compte rarement : les plus grands
sauts, et l'étape où une mauvaise heuristique commence à coûter plus qu'elle ne
rapporte.

**L'évaluation en cinquième, le réglage en dernier.** Un meilleur jugement aide
une fois la recherche assez profonde (pions passés, structure de pions, mobilité,
sécurité du roi). Le réglage ne peut pas créer une connaissance que l'évaluation ne
possède pas, seulement déplacer les paramètres vers un optimum local.

## 8.2 Pourquoi chaque étape rapporte moins

L'échelle est ordonnée, et c'est aussi une leçon sur les rendements décroissants.

- **La correction n'ajoute aucune force en soi :** son bénéfice est que toute
  mesure ultérieure signifie quelque chose.
- **La vitesse sature :** le doublement suivant coûte un projet et devient
  souvent hors d'atteinte une fois les gains évidents pris.
- **Ordonnancement et élagage se recouvrent :** après saturation, une heuristique
  de plus redistribue les nœuds au lieu d'approfondir la recherche.
- **Les termes d'évaluation se recouvrent :** un nouveau terme mesure en général
  ce que la recherche ou un terme existant couvre déjà, et son coût peut annuler
  son gain.
- **Le réglage atteint un optimum local,** et l'Elo est logarithmique : les
  derniers cent points coûtent bien plus que les premiers.

L'ordre compte plus que le catalogue : une recherche faible n'exploite pas une
évaluation fine.

## 8.3 Le plafond classique

Les moteurs artisanaux, dont l'évaluation est une somme de termes conçus à la
main et dont la recherche est un alpha-bêta à heuristiques, ont convergé vers un
plafond. Les plus forts, à l'époque de Rybka vers 2008, se situaient autour de
**3100 à 3200 Elo** sur les échelles de l'époque. Les raisons sont structurelles :

- L'évaluation est **linéaire et additive**, donc elle ne peut pas représenter
  les interactions entre termes, là où réside une grande partie de la
  compréhension réelle du jeu.
- Le **jugement positionnel**, comme les plans à long terme ou la compensation
  matérielle, s'exprime mal par un terme réglé à la main.
- La **sécurité du roi** reste un point faible connu : elle dépend d'interactions
  subtiles, pas d'un simple comptage.
- Ajouter toujours plus de termes **n'aide pas** au-delà d'un point : ils se
  recouvrent, et chacun coûte de la vitesse que la recherche préférerait dépenser
  en profondeur.

À ce niveau, les lacunes restantes ne sont pas un terme oublié, c'est la forme même
du modèle.

## 8.4 Ce que NNUE a changé

**NNUE** (Efficiently Updatable Neural Network) a brisé le plafond en changeant le
modèle. L'évaluation devient un petit réseau de neurones dont les entrées encodent
la position, en général chaque pièce non-roi relativement aux deux rois, entraîné
sur des millions de positions plutôt qu'écrit à la main. Son adoption a apporté
aux meilleurs moteurs classiques de l'ordre de **+400 Elo**, bien plus que
n'importe quel terme ajouté à la main. C'est un **changement de paradigme**, pas un
terme de plus :

- la connaissance est **apprise à partir de données**, et non conçue par un
  humain ;
- elle capture des **interactions** qu'une somme linéaire ne capte pas ;
- elle reste rapide car le réseau est **mis à jour de façon incrémentale** au fil
  des coups ;
- le progrès vient ensuite de **meilleures données et de l'entraînement**, une
  compétence qu'un auteur solo peut désormais tenter avec des outils ouverts.

L'autre paradigme est la lignée AlphaZero : un réseau profond avec une recherche
arborescente de Monte-Carlo, qui apprend par auto-jeu, à un coût de calcul bien
plus élevé. La voie artisanale reste une éducation complète ; aller au-delà
signifie NNUE, un autre projet bâti par-dessus un moteur classique.

## 8.5 Objectifs réalistes en solo

Un développeur solo peut aller loin avec des objectifs réalistes.

- **Un moteur qui joue correctement**, jamais illégal, survivant à une partie en
  interface : quelques semaines de travail avec ce guide et une suite de tests.
- **Autour de 2000 Elo** : une recherche alpha-bêta propre, une évaluation simple
  par phase, une gestion du temps raisonnable.
- **De 2400 à 2600 Elo**, niveau de club : un bon ordonnancement des coups, une
  quiescence avec SEE, une première évaluation sérieuse.
- **De 2700 à 3000 Elo** : toute la boîte à outils classique, mesurée et réglée.
- **Le plafond classique**, 3100 à 3200 : atteignable en principe, mais des années
  de travail et une mesure constante ; **au-delà**, cela signifie généralement
  NNUE, un second projet.

La dernière centaine d'Elo est la plus chère, et l'essentiel de l'effort passe dans
la discipline d'accepter que la plupart des idées ne marchent pas.

## 8.6 Ce qui marche, ce qui échoue

| À faire | Échoue ou reste marginal |
|---|---|
| Perft et une suite de self-tests avant tout le reste | ajouter des fonctionnalités sur un générateur de coups non vérifié |
| Profiler, puis rendre le chemin chaud rapide | micro-optimiser du code qui n'est pas chaud |
| Ordonnancement : hash, MVV-LVA, killers, history, counter-move | une heuristique d'ordonnancement de plus après saturation |
| Quiescence avec SEE et élagage delta | quiescence profonde sans test de sûreté |
| Aspiration, null move, LMR, futility, LMP | élagages et réductions sans base stable |
| Évaluation par phase : matériel, PST, pions, mobilité, roi | réécrire toute l'évaluation d'un coup |
| Régler sur des données d'**auto-jeu** (Texel, SPSA) | régler sur des parties humaines ; les résultats reflètent des fautes humaines |
| Valider chaque changement par SPRT et assez de parties | conclure d'un match court ; 300 parties résolvent ~30 Elo |

Deux habitudes séparent un moteur fort d'un moteur qui dérive : **tout mesurer**,
car l'intuition sur la force n'est pas fiable, et **conserver les résultats
négatifs**, car savoir ce qui échoue vous empêche de le refaire plus tard.

## 8.7 BabaChess comme exemple

BabaChess est un moteur artisanal classique, à peu près au niveau de GNU Chess
6.2.7. Ses gains sont venus dans l'ordre ci-dessus : correction par le perft et
146 self-tests, vitesse par les bitboards à attaques PEXT, puis ordonnancement des
coups, puis un important travail de recherche, puis une évaluation réglée à la Texel.

Les gains gardés ont survécu à de longs SPRT. L'ordonnancement counter-move et
history et la gestion du temps sont venus en premier ; un réglage Texel sur des
parties d'auto-jeu a ajouté plus de cent Elo, là où la même méthode sur des parties
humaines avait échoué ; plus tard, la connaissance des pions passés et un terme de
mobilité qui exclut les cases attaquées par les pions adverses ont gagné leur place
un par un.

Le reste est une longue liste d'idées mesurées et rejetées, conservées derrière des
paramètres neutres pour que l'arbre soit inchangé lorsqu'elles sont éteintes :
refonte de la sécurité du roi, mobilité par phase, plusieurs termes de
connaissance, échecs en quiescence, continuation history à deux plis, flag
« improving », terme d'imbalance matérielle, évaluation incrémentale et refonte de
la table de transposition. La table de hachage des pions a été écartée car
l'évaluation des pions est déjà bon marché, et l'optimisation guidée par profil s'est mesurée plus lente.
Sur ce moteur, elles se heurtaient à un **optimum local**, et la réponse honnête
était d'enregistrer la mesure et de passer à la suite.

L'échelle est réelle et les derniers barreaux sont là où le travail devient mesure
plutôt qu'inspiration. Un moteur classique est un projet complet, et son plafond
est une propriété du modèle, non un échec de son auteur.

## Voir aussi

- `02-board-and-movegen-fr.md` : correction, perft et générateur de coups.
- `03-evaluation-fr.md` : l'évaluation artisanale et ses limites connues.
- `04-search-fr.md` : les leviers, de l'alpha-bêta aux réductions et élagages.
- `05-opening-book-fr.md` et `06-endgame-tablebases-fr.md` : le livre et les
  tablebases, de la force peu coûteuse aux deux extrémités de la partie.
- `07-testing-fr.md` : perft, self-tests, SPRT, Texel et SPSA.
- `src/doc/outils-et-tests-fr.md`, `src/doc/evaluation-fr.md`, `src/doc/recherche-fr.md` :
  mesures, évaluation et recherche en détail.
- `src/doc/README-fr.md` et `DEVELOPMENT.md` : l'index technique et les journaux
  internes derrière ces mesures.
