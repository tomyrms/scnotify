# SnapNotify 4.0.0-rc2 — réception des chats et snaps

Correctif ciblé de la version `dd9471b02154b2def0f52981f26dced6e829c44e` du dépôt `tomyrms/scnotify`. Les fichiers de code de référence `Tweak.m` et `Sources/SNRuntime.m` ont été vérifiés contre les empreintes GitHub. Les deux changements présents dans cette version sont conservés : hooks ARC en `if/else` et `ExperimentalKeepAlive=true` par défaut. Une configuration utilisateur existante n'est pas écrasée.

**Sources complètes, pas un IPA ni une bibliothèque déjà compilée.** Les 78 tests Python/C et deux corpus de 100 000 entrées sous sanitizers passent dans l'environnement Linux de préparation. Les tests Foundation/macOS et la compilation iOS de **rc2** doivent encore passer sur le runner Mac. La réussite CI de rc1 ne vaut pas validation de rc2.

Le retour utilisateur confirme les appels et la saisie dans rc1, mais pas les chats/snaps. Le dernier fichier joint est une transcription de compilation ; il ne contient pas les événements de réception des nouveaux essais. Cette livraison corrige des défauts de code vérifiables et ajoute des adaptateurs de compatibilité, sans prétendre avoir observé des chats/snaps reçus sur l'iPhone.

## Correctif

Le récepteur lit désormais `descriptor.messageId`, `descriptor.conversationId`, `messageContent.contentType` et les métadonnées structurées. Une conversation passée séparément dans un callback explicite reste associée à ses messages. Les identifiants natifs enveloppés dans 16 octets et les identifiants de message `uint64_t` sont pris en charge sans conversion signée destructive. Les dates Unix en secondes, millisecondes, microsecondes et nanosecondes sont normalisées.

Les notifications « écrit », « message reçu » et « snap reçu » gardent des clés distinctes. Deux vrais messages avec deux identifiants restent deux événements ; un reçu de lecture, une suppression, une modification et un ancien message rechargé ne doivent pas être annoncés comme une nouvelle réception.

Les callbacks de réception directs et les mises à jour de conversation sont distingués. Les mises à jour prennent d'abord une référence initiale, puis comparent les identifiants et la date de création. Un premier chargement, une liste vide, un retrait/réajout ou un déchiffrement tardif d'un message déjà connu ne devient pas artificiellement une nouvelle réception. Ce chemin exige l'identité du compte local ou un indicateur entrant explicite. Les callbacks à quatre arguments objets sont maintenant supportés ; une signature scalaire incompatible est signalée, pas appelée avec un type arbitraire.

Les types numériques sont résolus par le descripteur d'enum de l'hôte lorsqu'il existe. Aucun tableau numérique Snapchat n'est inventé : un type inconnu reste rejeté et diagnostiqué. Un réglage avancé `ReceiveTypeMappings` permet une correspondance **Class.field** uniquement après vérification sur l'appareil ; il est vide par défaut.

## Compiler et installer

1. Copier **tout le projet**, y compris `Sources`, `Core`, `tests`, `scripts` et `.github`, dans le dépôt. Copier seulement `Tweak.m` ne suffit pas.
2. Lancer **SnapNotify tests and build** et attendre la réussite des tests portables, des tests Foundation et de la compilation arm64.
3. Récupérer **SnapNotify-v4-dylib**, remplacer `SnapNotify.dylib` dans le processus habituel de reconditionnement/signature, puis installer l'IPA. Ne pas empiler rc1 et rc2 dans le même binaire.
4. Vérifier `READY version=4.0.0-rc2` dans `snapnotify.log`. Ouvrir une fois la conversation du compte de test avant de mettre l'application en arrière-plan. Cela fournit une référence pour les observateurs de conversation.

Sur Mac avec Xcode : `make test`, `make test-macos`, puis `make`. Theos reste également supporté via `THEOS`.

## Test attendu

Depuis le deuxième compte, écrire puis envoyer un chat : une notification de saisie et, lorsque le message est réellement reçu, une notification de message distincte. Envoyer ensuite deux chats courts et deux snaps sans nouvelle saisie, puis refaire un appel. Recharger une conversation ne doit pas réannoncer l'historique.

Par défaut, les notifications locales sont supprimées au premier plan (`NotifyInForeground=false`). Faire le test avec l'application réceptrice en arrière-plan ; `NotifyInForeground=true` permet un essai diagnostic au premier plan. Le texte du chat n'est pas recopié : la bannière indique qui a envoyé un message ou un snap.

## Diagnostic de réception

`Documents/snapnotify_receive_schema.json` contient les callbacks trouvés, leur signature, le succès de leur installation, leurs compteurs et les raisons de rejet. Les descriptions d'objets et le contenu des messages ne sont pas exportés : les échantillons portent sur des noms de classes/champs, des noms de getters déclarés et, si nécessaire, une valeur numérique d'enum.

`snapnotify_status.json` ajoute `receiveCallbacks`, `decodedMessages`, `decodedSnaps`, `snapshotRecordsSuppressed`, `receiveQueueDrops`. Les compteurs « decoded » comptent les observations, y compris les doublons techniques : **pas des bannières affichées**. `NOTIF-ACCEPTED` reste une requête acceptée par iOS, pas une preuve d'affichage.

Après les tests, revenir au premier plan pour actualiser les fichiers. Le trio utile est `snapnotify.log`, `snapnotify_status.json`, `snapnotify_receive_schema.json`. Une absence totale de callbacks ne peut pas être réparée en diminuant encore le délai anti-doublons.

## Arrière-plan et limites

Le maintien expérimental en arrière-plan de la version utilisée est conservé, pas réécrit. Il reste expérimental, dépend du mode audio de l'IPA et peut perturber l'audio ou la batterie ; `ExperimentalKeepAlive=false` le désactive. Cette livraison n'ajoute aucun entitlement de signature et ne promet pas un accès push natif. Elle ne récupère ni ne télécharge elle-même les médias : elle transforme des événements observés dans l'application en notifications locales.

Les callbacks privés peuvent varier selon la version de Snapchat. Le rapport de diagnostic permet de distinguer un callback absent, une signature incompatible, un type non résolu, une date invalide et une notification dédupliquée. Sans les nouveaux journaux d'exécution, il n'est pas établi lequel de ces chemins correspond exactement au symptôme restant sur ton appareil.

## Documents

`docs/CORRECTION_CHATS_SNAPS.md` expose les modifications et leur niveau de preuve. `docs/TESTS_EFFECTUES.md` et `VALIDATION.json` décrivent la validation réelle. `docs/VALIDATION_IPHONE.md` donne le protocole de vérification. Les documents rc1 sont conservés dans `docs/history/rc1` et ne décrivent pas la validation actuelle.

Aucun journal privé brut, token, certificat, binaire Snapchat ou nouveau paquet prétendument capturé n'est inclus. Les nouveaux tests d'adaptateurs sont des fixtures synthétiques ; les anciennes trames d'appel anonymisées restent des tests de régression.
