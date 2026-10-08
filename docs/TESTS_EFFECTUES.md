# Validation effectuée — SnapNotify 4.0.0-rc5

## Résultat de compilation

La CI GitHub a réellement exécuté les tests et compilé la bibliothèque arm64 dans le run **37852967825**, job **113570291032**, commit **ebeccf68303f24106a1a29915a90c20b08b8e48b**. Résultat : **success**.

Lien : https://github.com/tomyrms/scnotify/actions/runs/37852967825

La branche isolée `chatgpt/rc5-voice-bursts-background` contient les nouveaux modules et un patch texte lisible. La CI vérifie son SHA-256 avant de l'appliquer à rc4. Le ZIP livré contient directement les sources intégrées ; il ne faut pas leur appliquer ce patch une deuxième fois. `main` n'a pas été modifié.

## Tests exécutés

**86 tests Python/C réussis**, localement sur Linux et dans la CI macOS. Deux corpus de **100 000 entrées** chacun ont été exécutés sous AddressSanitizer et UndefinedBehaviorSanitizer : aucune erreur signalée dans ces corpus. Ils couvrent le cœur C et la politique de réception, pas tout le runtime iOS.

Les cinq programmes Objective-C/macOS ont également été compilés puis exécutés :

| Programme | Assertions réussies |
|---|---:|
| Foundation/runtime | 50 |
| Adaptateurs de réception/runtime | 107 |
| Relais de notifications internes | 52 |
| Réception native | 8 402 |
| File persistante, rafales, types | 5 471 |

Ces nombres incluent des assertions répétées dans des boucles, **pas 14 082 scénarios indépendants**.

Le test de file enregistre **600 messages distincts**, recrée l'objet de file en lisant les fichiers, traite chacun avec un temps simulé bien supérieur à quinze secondes, puis vérifie les identifiants, l'absence de doublon et la restauration des succès. Il simule les erreurs temporaires, l'absence de réponse, les callbacks obsolètes, le refus d'autorisation, les identités de compte et les erreurs disque. Il vérifie sur les vrais fichiers qu'aucun nom ou corps de message n'est enregistré.

Les adaptateurs traitent **600 modèles natifs synthétiques en cinq lots** et **8 300 identifiants de snapshot successifs**, au-delà de l'ancien arrêt à 2 048. Les getters synthétiques de vocaux/stickers/photos/réponses sont couverts. Les tests du cache distant vérifient des temps à dix et trente minutes, l'isolation entre conversations et la remise à zéro. Il ne s'agit pas d'une exécution réelle de trente minutes sur iPhone.

## Correspondance de l'artefact livré

L'artefact **11583221063**, `SnapNotify-rc5-validated`, a été téléchargé. L'empreinte SHA-256 de son ZIP a été comparée à celle de GitHub. Celle de `SnapNotify.dylib` correspond à `SHA256SUMS.txt`. **Les 32 empreintes des sources et tests enregistrées après compilation correspondent toutes aux fichiers livrés.** Documentation, configuration exemple et rapport de livraison sont mis à jour séparément et ne changent pas le code compilé.

- Bibliothèque : 294 224 octets, Mach-O arm64, chaîne `4.0.0-rc5` présente.
- SHA-256 : `812e223a0bd0b3debf349ce77b28f5541f5b7ca885a824a1b53a97639a39aff6`.
- Preuve de compilation et extraits exacts : `CI_EXCERPTS_RC5.txt`.
- Informations du run : `../prebuilt/WORKFLOW_RUN.json`.
- Empreintes de sources produites en CI : `../prebuilt/SOURCE_HASHES.json`.

## Contrôles de livraison

Scripts shell analysés avec `bash -n`, plists vérifiées, fichiers Python parsables, empreintes de sources revérifiées, structure Mach-O et chaîne de version contrôlées, intégrité et chemins du ZIP vérifiés.

## Non réalisé

Aucun reconditionnement/signature d'IPA ni installation de rc5 sur l'iPhone ; aucune mesure d'autonomie ; aucun appel réel ; aucun envoi réel de vocal/chat/snap pour rc5 ; aucun test de bannière en rafale ; aucune preuve de maintien réseau pendant quinze ou trente minutes. Les tests de la file simulent le résultat de l'API de notification : **une acceptation API n'est pas la preuve d'un affichage visible**.

L'ancien schéma de l'appareil est un schéma rc3. Il étaye les noms de getters, mais n'est pas une trace de la nouvelle coupure signalée sur rc4. Il n'y a pas de nouvelle capture permettant de choisir avec certitude entre perte d'identité distante, interruption audio, fermeture réseau et suspension iOS.
