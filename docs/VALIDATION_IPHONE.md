# Vérification iPhone — rc5

Appareil cible déclaré : iPhone 14, iOS 26.6.2, Snapchat 14.17.1, installation Sideloadly. Ce protocole n’a pas été exécuté dans cette livraison.

1. Compiler avec la CI incluse; attendre tests et build réussis, remplacer l’ancienne dylib et relancer. Vérifier la version rc5 dans `READY`.
2. Autoriser les alertes et sons iOS. Pour tester au premier plan, définir `NotifyInForeground=true` dans la configuration EXISTANTE.
3. Avec un autre compte, envoyer un chat, un vocal, deux snaps, un sticker et un média de chat. Chaque ID distinct doit provoquer sa requête; les retransmissions du même ID restent uniques. Un vocal doit afficher « t’a envoyé un vocal » s’il expose un prédicat/type vocal reconnu.
4. Envoyer une rafale de 30 messages distincts. Comparer le nombre attendu aux deltas de `notificationRequestsAccepted`, au journal `NOTIF-ACCEPTED` et au centre de notifications. `notificationBacklog` doit revenir à zéro; `notificationBufferOverflows`, `receiveQueueDrops`, `packetDrops` et `notificationFailures` ne doivent pas augmenter. Une bannière unique pendant une rafale ne signifie pas forcément qu’une seule requête a été acceptée.
5. Laisser Snapchat en arrière-plan sans fermer sa carte; envoyer à 1, 5, 10, 15 et 30 minutes. Recommencer après un vocal et une interruption audio réelle. Ne pas inférer une réception à partir du seul lecteur audio.
6. Annuler un appel pendant l’attente du nom et vérifier qu’aucune notification tardive ne réapparaît. Si plusieurs comptes sont utilisés, vérifier qu’un retour de l’ancien compte n’annule pas les notifications du nouveau.

## Lire le diagnostic

- `receiveCallbacks` ne progresse plus : le tweak ne reçoit plus les callbacks. Examiner l’état audio, la connexion et la suspension; ce n’est pas un problème de texte de notification.
- Callbacks présents, `decodedMessages/decodedSnaps` immobiles : regarder les rejets dans `snapnotify_receive_schema.json`.
- Décodage présent mais pas d’envoi : examiner les filtres de date/direction, le réglage premier plan et la déduplication.
- `NOTIF-FAILED` : code et domaine d’erreur iOS. `NOTIF-ACCEPTED` signifie requête acceptée, pas affichage visuel confirmé.
- `background.audioBackgroundModeDeclared=false` : l’IPA ne déclare pas le mode audio requis par l’expérience. Modifier Info.plist seul ne garantit ni l’exécution ni les droits APNs.
- `background.audioPlaying=false` / `lastKeepAliveStop` : dernier motif d’arrêt. `secondsSinceMainHeartbeat` très élevé est compatible avec une suspension ou un blocage, sans les distinguer à lui seul. Le diagnostic est un instantané; il ne se met pas à jour pendant une suspension.

Conserver les trois fichiers `snapnotify.log`, `snapnotify_status.json`, `snapnotify_receive_schema.json`. Si possible conserver une copie avant de revenir au premier plan, puis une seconde après. Ne pas joindre certificat, mot de passe ou jeton d’appareil.

## Limites explicites

La file n’est pas persistée si iOS termine le processus. Elle est bornée à 8192 éléments, avec 16 envois en cours. Le décodeur limite chaque callback à 512 événements/4096 objets parcourus; le suivi limite 2048 IDs frais par conversation et 128 conversations. Les seuils défensifs ne promettent pas un nombre infini de notifications. Une notice native sans ID stable ne permet pas de distinguer parfaitement deux textes identiques de deux callbacks du même événement. Le maintien audio ne garantit pas la reconnexion du canal Snapchat.
