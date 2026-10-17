# 5. Le livre d'ouvertures

Un moteur livré à lui-même s'engage parfois, dès les premiers coups, sur des
lignes faibles que son évaluation statique ne pénalise pas assez tôt. Le livre
d'ouvertures corrige ce biais : il ne réfléchit pas, il joue un coup connu et
rend la main à la recherche. C'est un composant latéral, consulté **avant** que
la recherche ne prenne le relais, au même titre que les tablebases de finales.
Ce chapitre explique à quoi il sert, comment il est représenté, comment on le
sonde et comment on en fabrique un. BabaChess sert d'exemple.

## 5.1 Pourquoi un livre

Un livre d'ouvertures apporte trois choses distinctes.

- **Éviter les erreurs précoces.** L'ouverture est riche en pièges que
  l'évaluation statique juge mal ; une ligne éprouvée évite de répéter un coup
  douteux que rien ne punit assez tôt.
- **Gagner du temps.** Un coup de livre est joué instantanément : le temps
  épargné est réinvesti plus tard, dans le milieu de partie, là où le calcul
  compte vraiment.
- **Varier.** Un livre pondéré propose plusieurs coups par position et en tire un
  au hasard, ce qui évite de rejouer toujours la même partie.

Le livre ne remplace ni l'évaluation ni la recherche : il les précède, sur une
poignée de demi-coups seulement.

## 5.2 Les formats de livre et Polyglot `.bin`

Un livre est une table associant une position à une liste de coups. Les formes
varient : listes dérivées de PGN, ou fichiers binaires compilés. Le format
**Polyglot `.bin`** s'est imposé comme le standard de fait : simple et compact,
il est lu par la plupart des moteurs et des interfaces.

Un livre Polyglot est un fichier binaire sans en-tête, composé d'entrées de
**16 octets**, au format gros-boutiste (*big-endian*) et **triées par clé
croissante** :

| Taille | Champ | Rôle |
|---|---|---|
| 8 | `key` | clé Zobrist Polyglot de la position |
| 2 | `move` | coup encodé (départ, arrivée, promotion) |
| 2 | `weight` | fréquence relative du coup |
| 4 | `learn` | réservé, ignoré |

Le tri par clé autorise une **recherche binaire**, donc un sondage en `O(log n)`
même dans un livre de plusieurs centaines de milliers d'entrées. Le champ
`weight` sert de probabilité relative : un coup joué souvent pèse plus qu'un coup
rare. Cette compatibilité permet de réutiliser un livre public sans conversion.

## 5.3 Comment fonctionne un sondage

Sonder un livre, c'est retrouver une position pour en tirer un coup. On calcule
d'abord la **clé Zobrist Polyglot** de la position. Ce n'est pas la clé de la
table de transposition : le format fixe sa propre convention, avec une table de
constantes figées et une règle particulière sur la prise en passant, car le livre
doit correspondre octet pour octet à ce qu'ont produit les générateurs externes.

Le sondage se déroule en plusieurs temps :

1. calculer la clé de la position ;
2. chercher cette clé par recherche binaire dans le tableau trié ;
3. balayer les entrées contiguës de même clé et additionner leurs poids (chaque
   poids étant plancher à 1, pour qu'une entrée de poids nul reste jouable) ;
4. tirer un nombre aléatoire dans cette somme et sélectionner l'entrée
   correspondante : c'est le **choix pondéré** ;
5. décoder le coup et **vérifier qu'il est réellement légal**.

La dernière étape est essentielle : un livre peut contenir des coups périmés ou
une promotion mal encodée. Le sondage ne renvoie donc jamais un coup illégal ; si
la clé est absente ou si le coup décodé n'est pas légal, le livre est muet et la
recherche normale démarre.

En amont, le pilote décide **s'il faut consulter** le livre : il doit être activé
et chargé, et la position ne doit pas être trop avancée. Un moteur limite en
général le sondage à une quinzaine de demi-coups.

## 5.4 Construire un livre depuis une base publique

On fabrique un livre en comptant les coups joués dans une grande base de parties.
La base **Lichess**, publiée sous licence **CC0** (domaine public), est
réutilisable, y compris dans un projet sous GPL. On choisit une période, on
comptabilise pour chaque position les coups joués et leur résultat, puis on
transforme ces statistiques en entrées Polyglot, avec un poids dérivé de la
fréquence et du score.

Une base brute contient beaucoup de bruit : sans **filtres**, le livre n'est pas
utile. Les réglages typiques :

- **niveau des joueurs** : seuil Elo minimal pour les deux camps ;
- **cadence** : écarter les parties trop rapides ;
- **profondeur** : ne garder que les premiers demi-coups ;
- **fréquence** : nombre minimal d'occurrences d'une position et d'un coup ;
- **part de coup** : écarter les coups marginaux et ceux au résultat trop faible ;
- **largeur** : plafonner le nombre de coups par position.

Un filtrage optionnel par un moteur fort écarte en plus les coups douteux, mais
chaque filtre durcit le livre et peut faire disparaître des lignes importantes.
Le compromis **taille / qualité** est le vrai sujet : un seuil trop strict rate
des réponses courantes, un seuil trop laxiste admet des coups faibles. On calibre
donc les seuils sur un objectif de couverture, puis on valide le résultat.

## 5.5 Livre léger ou livre profond

La taille du livre n'est pas un but en soi, c'est un arbitrage.

- Un **livre léger** se charge vite, tient en peu de mémoire et couvre les
  grandes lignes ; il suffit à donner au moteur une ouverture saine.
- Un **livre profond** couvre plus de variantes, y compris rares, au prix d'un
  fichier plus gros, d'un chargement plus lent et d'un risque accru de coups de
  qualité inégale.

Pour un moteur qui joue, un livre modeste et propre vaut mieux qu'un livre
encyclopédique mal filtré ; pour de l'analyse, un livre plus large trouve sa
place.

## 5.6 Livre et équité en match

Le livre change le résultat des parties : il compte quand on mesure la force d'un
moteur.

- **Neutraliser le livre des deux côtés.** Sinon, la comparaison ne mesure plus
  la recherche mais l'ouverture.
- **Ne pas partir de la position initiale seule.** Une partie lancée depuis le
  début est biaisée en faveur des Blancs, dont le taux de victoire approche 70 %.
  On utilise une **suite d'ouvertures** et on joue chaque ligne dans les deux
  couleurs.

Autrement dit, le livre sert à **jouer**, pas à mesurer la force brute.

## 5.7 BabaChess comme exemple

BabaChess illustre chaque point. Le module s'appelle `BBChess.Polyglot` et vit
dans `src/bbchess-polyglot.adb` / `src/bbchess-polyglot.ads`. Il implémente le
format Polyglot `.bin` et se sonde **avant** la recherche, avec une limite de
**16 demi-coups** : au-delà, la recherche reprend la main.

Trois voies ouvrent un livre : l'option `--book <fichier>`, des emplacements
conventionnels chargés par défaut (dont `books/book.bin`), et les options UCI
`OwnBook` (activé par défaut) et `BookFile`. Un livre embarqué de **0,58 MiB**
est fourni : **38 191 entrées** générées depuis la base Lichess **CC0**, non
versionné car reproductible. `scripts/make_book.py` le construit et
`scripts/fetch_book.sh` récupère un livre CC0 prêt à l'emploi.

Point notable : `--selftest` ne charge **pas** le livre ; la validation vérifie
la **clé Zobrist Polyglot**, confrontée à des valeurs de référence externes.

## Voir aussi

- `src/doc/ouvertures.md` : la documentation de référence du livre BabaChess
  (format, clé Polyglot, sondage, configuration, vérification).
- `books/README.md` : provenance du livre embarqué (Lichess CC0), réglages,
  régénération et validation.
- `scripts/make_book.py` : construction d'un livre Polyglot depuis Lichess, avec
  les filtres et la validation.
- `scripts/fetch_book.sh` : téléchargement d'un livre CC0 déjà généré.
- Code : `src/bbchess-polyglot.adb` et `src/bbchess-polyglot.ads` (clé Polyglot,
  chargement du `.bin`, sondage pondéré).
- `src/doc/README.md` : l'index de la documentation technique.
- Chapitre voisin : `04-search-fr.md` ; les autres chapitres sont dans `docs/`.
