# Provenance du schéma de présence

Implémentation primaire indépendante inspectée :

[SE-Extended / SnapEnhance — FriendTracker.kt, commit be815bbf435d8ece4514b390dc6dbbf2ee81c0aa, lignes 169–189](https://github.com/CoffeeBrewer64/SE-Extended/blob/be815bbf435d8ece4514b390dc6dbbf2ee81c0aa/core/src/main/kotlin/me/rhunk/snapenhance/core/features/impl/spying/FriendTracker.kt#L169-L189).

La source lit le champ 6 comme conversation, les champs 4 répétés comme participants, leur champ 1 comme identifiant `uuid:session` et leur champ 2 → 1 comme drapeaux de présence. Elle distingue composition (bit 4) et `speaking` (bits 4 et 6 ensemble). L’enveloppe de transport identifie le topic `presence`.

Cette preuve concerne le protocole. Elle ne démontre pas l’équivalence avec l’enum numérique iOS `typingState`, qui reste non interprété. Le libellé « enregistre un vocal » est l’interprétation de l’état de composition vocale; elle doit être confirmée par un essai contrôlé sur Snapchat iOS 14.17.1.

Le décodeur C de rc7 est une implémentation nouvelle utilisant le lecteur borné existant du projet. Aucun code tiers de suivi, aucune inscription à un nouveau canal réseau, aucun endpoint et aucun mécanisme d’accès à un compte ne sont intégrés.
