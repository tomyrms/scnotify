# Validation réellement effectuée — 4.0.0-rc2

## Exécuté dans l'environnement de préparation

Commande : `bash scripts/test-portable.sh` sur Linux, Clang 17, Python 3.

**78 tests Python/C : tous réussis.** Ils chargent le cœur C et la nouvelle politique de réception compilés ; il ne s'agit pas d'une réimplémentation Python de ces fonctions. Cela comprend les 54 tests de base (identifiants, enveloppes, appels, saisie, registre anti-doublons et inspecteur d'IPA) et 24 nouveaux tests de politique de réception (avec plusieurs sous-cas).

**100 000 entrées déterministes sur le cœur existant**, plus les troncatures de la fixture d'appel, sous AddressSanitizer et UndefinedBehaviorSanitizer : aucune erreur signalée dans le corpus exécuté.

**100 000 entrées supplémentaires sur la politique de réception**, sous les mêmes sanitizers : aucune erreur signalée dans le corpus exécuté. Ce test exerce les chaînes de classification/sélecteurs et des représentations flottantes variées ; ce n'est pas un fuzzer de l'adaptateur Objective-C.

Les 14 anciennes trames d'appel anonymisées restent couvertes par le rejeu existant. Elles ne sont pas des captures de chats/snaps. Aucun résultat de test n'est présenté comme une bannière vue sur l'iPhone.

Contrôles de livraison : scripts shell analysés avec `bash -n`, fichiers Python compilés avec `py_compile`, plists analysées avec `plistlib`, fichiers de compilation cohérents, fonctions d'appel/pré­sence et cœur C comparés à la base, intégrité et chemins de l'archive vérifiés. Sortie complète des tests portables : `portable-tests.txt`.

## Fourni, mais non exécuté ici

`tests/TestFoundation.m` et `tests/TestReceive.m` requièrent Foundation et le runtime Objective-C macOS. Le runner Linux de préparation ne les exécute pas. Le nouveau programme comprend des fixtures synthétiques pour les descripteurs, UUID natifs, IDs uint64, enums hôtes, conversation séparée, tableaux, cycles, contrôle/historique/sortant, dates, référence initiale vide, déchiffrement tardif et hook à quatre arguments. La CI doit encore confirmer leur résultat.

Le workflow `.github/workflows/build.yml` compile et exécute ces deux programmes avant de compiler et publier `SnapNotify.dylib`. Il n'ignore pas leurs erreurs. **Le workflow rc2 n'a pas été lancé depuis cette livraison ; compilation iOS rc2 non effectuée.** La CI réussie mentionnée dans le texte joint concerne rc1, commit `dd9471b`.

## Non réalisé

Aucun test d'installation ou d'exécution de rc2 sur iPhone ; aucun envoi réel de chat/snap ; aucune mesure d'autonomie ; aucun test prouvant le maintien réseau après suspension. L'absence de nouvelles traces de l'appareil interdit d'attribuer le problème restant avec certitude à un callback privé précis.
