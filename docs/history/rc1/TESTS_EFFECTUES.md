# État de validation — 8 octobre 2026

## Exécuté dans l'environnement de préparation (Linux, Clang)

**54 tests automatisés réussis.** Les 48 tests du cœur compilent et chargent le fichier `Core/SNCore.c` utilisé par la bibliothèque iOS, pas une réécriture Python de ses algorithmes. Six autres tests vérifient l'inspecteur d'IPA et son absence de modification du fichier d'entrée.

Les tests couvrent les UUID, enveloppes Protobuf, données tronquées, champs dupliqués, limites de taille, actions d'appel, vrais booléens JSON, Unicode, JSON mal formé, absence de faux appels issus de sous-chaînes, réarmement de saisie après 120 secondes, absence de spam durant une saisie continue, séparation des utilisateurs, annulation/confirmation de réservation, retransmissions, collisions de callbacks tardifs et registre borné.

**100 000 entrées de mutation/aléatoires, plus toutes les troncatures de la trame de départ, ont été exécutées avec AddressSanitizer et UndefinedBehaviorSanitizer.** Aucun défaut n'a été signalé dans ce corpus. Ce résultat ne prouve pas l'absence de tout défaut mémoire possible.

**Rejeu de 14 trames complètes anonymisées de `snapnotify(3).log`.** Dix trames sont des actions d'appel et quatre concernent le transport. La simulation d'acheminement utilisant le décodeur et le registre de production décide d'une seule notification d'appel en arrière-plan ; les `STOP` et la retransmission ne créent pas de nouveaux messages. Les UUID, adresses, identifiants de tentative et données de portée ont été remplacés dans les fixtures.

La syntaxe des scripts Python et Bash, les deux fichiers plist et le workflow YAML ont aussi été vérifiés. Une compilation minimale Objective-C a confirmé la validité syntaxique du boxing des UUID C et de l'utilisation de `Class *` avec ARC ; **ce n'est pas une compilation du projet iOS**.

Commande reproductible :

```sh
bash scripts/test-portable.sh
```

La sortie de référence est conservée dans `docs/portable-tests.txt`.

## Fourni, mais non exécuté ici

`tests/TestFoundation.m` et `scripts/test-macos.sh` vérifient les lecteurs de propriétés, noms Unicode, UUID objets/binaires, snapshots multi-participants, repli des proxies, rejet d'événements sortants/historiques et sécurité des wrappers dans une hiérarchie Objective-C. Ces tests nécessitent Foundation et le runtime macOS ; ils ne sont pas inclus dans le chiffre des 54 tests réussis.

Le workflow GitHub Actions doit ensuite exécuter ces tests, puis `scripts/build-macos.sh`. Aucun runner distant n'a été lancé et **aucune compilation/link iOS arm64 n'a été réalisée dans l'environnement de préparation**, qui ne dispose pas du SDK Xcode. Aucun `.dylib` ni IPA prétendument compilé n'est donc fourni dans cette archive.

## À confirmer sur l'iPhone

La présence effective des méthodes privées de Snapchat, la résolution réelle des noms, l'arrivée des réceptions de snaps/messages, l'affichage des bannières, le fonctionnement sous écran verrouillé, le mode expérimental de maintien et l'absence d'interférence avec les appels/le micro restent des tests sur appareil.

Les sources corrigent des défauts identifiés et les comportements déterministes testables. **Le statut de cette livraison est une version candidate, pas une certification de fonctionnement complet dans ton Snapchat.**
