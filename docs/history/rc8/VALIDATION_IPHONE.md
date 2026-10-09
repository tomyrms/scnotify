# Validation iPhone rc8

À exécuter après compilation et injection sur Snapchat 14.17.1.

1. Vérifier `READY version=4.0.0-rc8`. Autoriser les notifications iOS et activer `NotifyInForeground` pour l’essai avec Snapchat ouvert.
2. Depuis un autre compte, envoyer un vocal, puis un chat immédiatement après. Refaire en quittant l’écran de Snapchat entre les deux, sans forcer la fermeture du processus. Vérifier les entrées du Centre de notifications en plus des bannières transitoires.
3. Envoyer dix chats distincts rapidement, y compris deux textes identiques. Refaire avec vocal → chat → vocal et avec deux contacts. Compter les notifications de réception séparément des alertes de saisie.
4. Tester un bref arrêt/reprise de saisie pendant une réception : il doit annuler seulement la préparation devenue obsolète, pas le message reçu.
5. Refaire après écoute d’un vocal, puis après enregistrement d’un vocal. Tester encore à 10 et 20 minutes en arrière-plan et après retour dans l’app. Noter les heures exactes et l’état de l’écran pour comparer les diagnostics.
6. Vérifier les deux libellés de présence texte/vocal de rc7. Une activité de type inconnu continue d’attendre des informations explicites.

## Interpréter une perte

- `receiveCallbacks`, `secondsSinceReceive` et `secondsSinceWire` indiquent si les hooks continuent de voir des données.
- `RECEIVE ... eligible=...` indique combien d’événements ont passé les filtres. Les raisons rejetées sont disponibles dans `snapnotify_receive_schema.json`.
- `NOTIF-REQUEST` indique une soumission à iOS; `NOTIF-ACCEPTED ... late=1` confirme une acceptation traitée après expiration du délai local. Cela ne prouve pas une bannière visible.
- `notificationTimeouts` compte les échéances dépassées, séparément de `notificationFailures`. `lateNotificationAcceptances` compte les acceptations tardives préservées.
- `notificationBacklog`, `notificationInFlight`, `notificationBufferOverflows`, `receiveQueueDrops` et `packetDrops` aident à identifier une saturation.
- `background.audioPlaying`, `background.audioCategory` et `background.lifecycleDeferred`, avec les lignes `KEEPALIVE-UNAVAILABLE`, permettent de distinguer la session audio d’un problème de déduplication. `host-recording-or-call` signifie que la catégorie audio de Snapchat a empêché le maintien expérimental.

Si l’essai échoue encore, conserver `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`, en indiquant l’heure du vocal reçu et celle du chat manquant. Les diagnostics n’exportent pas le corps des messages; ne pas joindre l’IPA ni des identifiants de connexion.

Ce correctif préserve les messages qui parviennent aux adaptateurs. Il n’assure pas une reconnexion du canal Snapchat ni une exécution permanente sous iOS. Le son demeure celui des alertes iOS par défaut.
