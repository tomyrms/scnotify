# Changements rc3

## Base et périmètre

Base vérifiée : code du commit `d718a6b4de438362453f8b3467d9d41d3618cc91` (`facbeb1` pour la dernière modification de code). Les corrections ARC et cycle de rc2 sont conservées. Les fichiers du cœur C et `SNRuntime.m` restent identiques à cette base.

## Récepteurs réseau

`Tweak.m` observe `registerHandler:handler:queue:` sur le client Duplex identifié dans les logs. Il conserve le topic en association avec le récepteur et instrumente son implémentation de `onReceive:` avec le mécanisme de hook sûr existant. Deux récepteurs supplémentaires déjà identifiés sont également couverts si l'enregistrement a précédé le scan. Les associations nouvelles ne changent ni les files hôtes ni les abonnements réseau.

Les données JSON/objets structurées passent au décodeur. Les enveloppes binaires déjà prises en charge conservent leur traitement précédent pour les appels et la présence. Le code ne prétend pas disposer d'un déchiffreur ou du schéma complet de tous les canaux.

## Notifications internes

`SNHostNotice` ajoute un repli sur un titre et un corps déjà préparés par l'application. Ce repli n'est appelé que depuis des chemins explicites de présentation interne. Il ne recherche pas « snap », « call » ou « message » dans les octets reçus pour fabriquer un événement.

Le sélecteur `matchInAppNotification:systemNotification:` fait l'objet d'un traitement dédié : le bloc de la branche interne n'est enveloppé que si sa signature ABI est compatible. L'original est appelé une fois ; la branche système est inchangée. Les tests vérifient notamment les blocs incompatibles, les exceptions d'observation et le nombre d'appels à l'original. Référence ABI : https://clang.llvm.org/docs/Block-ABI-Apple.html.

Le relais interne a sa propre déduplication, distincte de la saisie. Un identifiant interne est privilégié ; à défaut, le couple titre/corps est regroupé sur une seconde. Aucun texte de message n'est écrit dans les diagnostics. L'aperçu peut néanmoins apparaître dans la notification locale : il reste contrôlé par les réglages d'aperçu iOS.

## Instantanés et décodage tardif

Le premier lot n'est plus systématiquement assimilé à de l'historique. Il peut produire un événement si le message est entrant et daté après le début d'observation. Un compte local connu sert à établir le sens du message ; sinon un indicateur entrant explicite est nécessaire.

Les identifiants inconnus apparus après la référence initiale disposent d'une attente bornée pour leur décodage ultérieur. Ils ne deviennent pas définitivement « vus » avant d'avoir pu être compris. Les identifiants présents dans la référence historique initiale ne déclenchent pas de notification lors de leur déchiffrement tardif.

Les limites restent conservatrices : un message sans date, un ancien message ou un type inconnu peuvent encore être rejetés sur la voie des instantanés. Les callback directs de réception et le relais interne sont des voies distinctes.

## Champs et diagnostics

Prise en charge de l'expéditeur porté par le descripteur, d'enveloppes `latestMessage`/`lastMessage` et des champs protobuf optionnels absents. Les assertions de direction explicites sont prises en compte sans attribuer arbitrairement un participant de conversation comme expéditeur.

Le fichier `snapnotify_receive_schema.json` contient désormais `transportSources`. Le statut contient `nativeNoticeCandidates`, `nativeNoticesAccepted` et `apnsDeliveryCallbacks`. Un succès d'ajout dans `UNUserNotificationCenter` reste une acceptation de requête, pas une preuve de bannière vue à l'écran.

## Non modifié / non garanti

Aucun hook global de notifications système, aucune modification des autorisations/signatures, aucune commande de synchronisation privée devinée, aucune nouvelle tâche BGTaskScheduler. Le maintien audio expérimental de la base reste présent avec ses limites existantes. La couverture des structures privées sur l'iPhone de l'utilisateur n'est pas validée par les fixtures macOS.
