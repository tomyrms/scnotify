# SnapNotify 4.0.0-rc3 — réception et notifications internes

Correctif pour ta propre installation de Snapchat. Base : `tomyrms/scnotify`, commit `d718a6b4de438362453f8b3467d9d41d3618cc91`. Les appels et la machine à états de présence ne sont pas réécrits.

**Cette version a été compilée pour iOS arm64 et testée sur le runner macOS. Elle n'a pas été installée ni testée sur un iPhone pendant sa préparation.** Le retour utilisateur « appels et saisie fonctionnent » concerne la version précédente, pas rc3.

## Utiliser la bibliothèque déjà compilée

[Artefact SnapNotify-rc3-validated](https://github.com/tomyrms/scnotify/actions/runs/37843432418/artifacts/11578248481) — [exécution CI et journaux](https://github.com/tomyrms/scnotify/actions/runs/37843432418). Une connexion GitHub peut être demandée. La conservation configurée est de 14 jours ; ensuite, reconstruire depuis les sources de ce ZIP.

Avec GitHub CLI connecté à ton compte :

```sh
gh run download 37843432418 --repo tomyrms/scnotify --name SnapNotify-rc3-validated --dir rc3-artifact
```

La bibliothèque se trouve dans `out/SnapNotify.dylib` dans l'artefact. Sa somme de contrôle se trouve dans `out/SHA256SUMS.txt`. `out/SOURCE_HASHES.json` décrit les fichiers exacts utilisés pour les tests et la compilation. Ces 26 empreintes ont été comparées avec les sources de cette archive : elles correspondent toutes.

Ce ZIP contient les **sources**, pas un IPA signé ni une copie du binaire GitHub. La branche `chatgpt/rc3-notification-validation` est une branche technique de validation : son workflow applique un patch vérifié avant de compiler. Ne pas prendre les fichiers non patchés de cette branche pour les sources rc3 ; utiliser cette archive complète. `main` n'a pas été modifiée par cette livraison.

## Installer

Remplacer l'ancienne `SnapNotify.dylib` dans le processus d'injection/signature habituel, sans empiler deux versions. L'IPA Snapchat original n'étant pas fourni dans cette demande, aucun IPA n'a été reconditionné ici. Conserver les extensions et les réglages de signature existants ; aucun ajout automatique de droit APNs ou de tâche BGTaskScheduler n'est effectué.

Ouvrir l'application et vérifier `READY version=4.0.0-rc3` dans `snapnotify.log`. Les anciens paramètres de `Documents/SnapNotifyConfig.plist` restent prioritaires. L'exemple fourni n'est pas une instruction d'écraser une configuration existante.

## Ce qui change

Le récepteur observe les objets réellement enregistrés avec `registerHandler:handler:queue:`, ainsi que les récepteurs Hermod/sync déjà identifiés dans les anciens logs. Un nom de canal ne devient pas une notification : seules les données structurées reconnues sont traitées. Les paquets opaques restent diagnostiqués.

Un pont de notifications internes récupère le texte déjà préparé par Snapchat sur des chemins explicites de présentation. Il ne nécessite pas un UUID de conversation et un identifiant de message quand l'hôte a déjà construit un titre et un corps de notification. Le callback original reste appelé ; la branche de notification système n'est pas interceptée comme une nouvelle réception.

Le premier lot d'une conversation peut désormais notifier un message **entrant, daté et créé après le début de l'observation**. Un nouveau message apparu après la référence initiale peut aussi être notifié lorsqu'il devient décodable. L'ancien historique reste silencieux. Les champs d'enum optionnels absents ne sont plus confondus avec une valeur numérique inconnue.

Détails : [changements](docs/CHANGEMENTS_RC3.md), [vérification du document DeepSeek](docs/VERIFICATION_DEEPSEEK_FR.md), [tests effectués](docs/TESTS_EFFECTUES.md), [essai iPhone](docs/VALIDATION_IPHONE.md).

## Réglages

`NativeNotificationBridge=true` active le nouveau relais de notifications internes. Il reprend du texte de notification déjà fourni par l'hôte ; cela peut inclure un aperçu de message. Le contenu n'est pas écrit dans les journaux SnapNotify, mais il peut être affiché par iOS selon les réglages d'aperçu de l'utilisateur.

Ce relais de secours n'est pas une classification chat/snap : une notification interne dépourvue de type ne permet pas une sélection fine par catégorie. Il est désactivé lorsque les notifications de messages **et** de snaps sont désactivées. Pour exclure entièrement cette voie, définir `NativeNotificationBridge=false`.

`ExperimentalKeepAlive=true` reste la valeur par défaut de la base utilisée. Il s'agit du mécanisme existant, pas d'une garantie de fonctionnement après suspension/fermeture forcée. En cas de gêne audio ou d'autonomie, mettre cette option à `false`. [Limites d'exécution iOS](https://developer.apple.com/forums/thread/685525).

## Reconstruire

Sur un Mac équipé de Xcode :

```sh
make test
make test-macos
make
```

Le Makefile prend également en charge Theos. Sur GitHub, remplacer **tout le projet**, notamment `Sources`, `Core`, `scripts`, `tests` et `.github`, puis lancer le workflow `SnapNotify tests and build`. L'artefact de ce workflow normal reste nommé `SnapNotify-v4-dylib`.

## Limites connues

L'analyse statique des IPA WhatsApp rapportée par DeepSeek n'a pas été reproduite : les IPA/profils originaux ne sont pas joints. Les derniers logs de l'appareil fournis sont ceux de v3 ; ils ne montrent pas un essai de réception rc3. Les adaptateurs restent dépendants des objets exposés par la version de Snapchat installée.

Le relais interne ne peut pas inventer une notification que Snapchat ne construit jamais, ni décoder un paquet chiffré opaque. Sans identifiant partagé entre deux chemins, une déduplication parfaite entre notification interne et réception structurée n'est pas garantie. Deux notifications internes identiques sans identifiant dans une seconde peuvent être regroupées. Les protections de volume restent bornées (notamment 2 048 identifiants retenus par conversation dans le suivi des instantanés).

Les rapports de versions précédentes restent dans `docs/history/rc2/` ; leurs résultats et limitations ne sont pas le rapport de validation rc3.
