# Validation réellement exécutée — 4.0.0-rc4

## Exécuté ici

Commande `bash scripts/test-portable.sh`, sur Linux avec Clang et Python 3 : **86 tests C/Python réussis**. Les huit tests ajoutés chargent la vraie fonction C de correspondance native, pas une réimplémentation Python. Ils couvrent SNAP=0, CHAT=1, la version et la classe autorisées, les valeurs non prises en charge, l'exclusion des métriques, le maintien du callback Arroyo et le refus de nombres génériques comme types symboliques.

Les deux corpus existants, de **100 000 entrées chacun**, sont passés sous AddressSanitizer et UndefinedBehaviorSanitizer sans erreur signalée : cœur C et politique de réception. Ils ne couvrent pas l'exécution des nouveaux objets Foundation.

Le résultat brut est dans `portable-tests-rc4.txt`. Les contrôles de livraison incluent la syntaxe des scripts shell, les fichiers Python, les plists, la compilation C avec warnings traités comme erreurs, les différences de code et l'intégrité du ZIP. Les fonctions de décodage des appels, de traitement de présence, de livraison et de maintien audio restent identiques à la base rc3 (rapport `UNCHANGED_PATHS.json`).

## Fourni mais NON exécuté ici

`tests/TestNativeReceive.m` ajoute des fixtures synthétiques reproduisant les noms de classes/champs de l'appareil : UUID `toString`, descripteur natif uint64, enum numérique, prédicats sémantiques, contrôles/sortants, paramètres Arroyo, historique/suppressions exclus, preuve du sens entrant, réévaluation de direction et retours BOOL/B/c. Les trois programmes Foundation précédents sont conservés, avec l'attente BOOL du test générique mise à jour.

Le script `scripts/test-macos.sh` compile et lance ces **quatre programmes** avant le build iOS dans le workflow normal du projet. Leurs résultats rc4 restent **inconnus** jusqu'à exécution sur Mac.

## Compilation et dépôt distant

L'environnement local ne dispose pas des SDK Apple. La tentative de création d'une validation CI isolée a été bloquée avant la création d'un arbre, d'un commit ou d'une branche. Aucun workflow rc4 n'a donc été lancé et aucune bibliothèque rc4 n'a été produite ici. Un blob préparatoire non référencé a été créé ; il n'a pas modifié `main` ni les fichiers d'une branche. Aucun résultat de validation rc3 n'est réutilisé comme preuve de compilation rc4.

## Non réalisé

Aucune installation rc4 sur iPhone ; aucun snap/chat réel reçu avec rc4 ; aucune mesure d'autonomie ; aucune garantie d'exécution réseau après suspension iOS. La réussite des tests C ne suffit pas à prouver la correction de bout en bout. Le correctif supprime une cause de rejet directement observée ; d'autres filtres peuvent encore nécessiter une validation sur l'appareil.
