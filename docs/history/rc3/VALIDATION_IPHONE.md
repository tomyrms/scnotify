# Essai sur iPhone — rc3

## Préparer

Utiliser la bibliothèque de l'artefact rc3 référencé dans le README, ou reconstruire tout le projet. Remplacer l'ancienne injection plutôt qu'en ajouter une deuxième. La signature finale et l'installation restent celles du processus habituel de l'utilisateur.

Lancer Snapchat manuellement et rechercher `READY version=4.0.0-rc3` dans `snapnotify.log`. Une ligne ancienne rc1/rc2 n'est pas suffisante. Vérifier dans le statut que les notifications sont autorisées ; conserver les réglages d'aperçu souhaités. Une ancienne configuration personnalisée peut désactiver `MessageNotifications`, `SnapNotifications` ou le maintien expérimental.

## Essai principal

Avec le compte destinataire, ouvrir la liste de conversations, puis laisser Snapchat en arrière-plan **sans balayer sa carte pour la fermer**. Noter l'heure, le réseau utilisé et si l'écran est verrouillé.

Depuis le second compte : écrire puis envoyer un chat, attendre quelques secondes, envoyer un deuxième chat sans nouvelle session de saisie, puis envoyer deux snaps. Refaire ensuite un appel et une nouvelle saisie. Conserver les heures précises pour corréler les logs. Effectuer un essai après 10 secondes en arrière-plan, puis un autre après deux minutes ; ce sont des conditions de test, pas des garanties de délai.

Le résultat attendu est une notification de saisie indépendante de celle du chat, ainsi que des notifications pour les deux snaps distincts lorsque ces réceptions sont observables par le mod. L'appel et la reprise de saisie ne doivent pas régresser. Ouvrir une ancienne conversation ne doit pas réannoncer son historique.

## Distinguer les étapes

- `TRANSPORT-REGISTER` indique un récepteur observé, pas la réception d'un chat.
- `transportSources` compte les callbacks des récepteurs ; `WIRE-UNSUPPORTED` signale un format non décodé, pas nécessairement un paquet corrompu.
- `RECEIVE` / les raisons de rejet du schéma montrent le résultat de l'adaptateur.
- `NATIVE-NOTICE-REQUEST` correspond au relais d'une notification interne déjà formée.
- `NATIVE-NOTICE-ACCEPTED` / `NOTIF-ACCEPTED` signifie qu'iOS a accepté la requête locale, pas que sa bannière a été affichée.
- `APNS-REGISTERED` signifie qu'un jeton a été obtenu. `apnsDeliveryCallbacks` compte les callbacks dans ce processus, pas toutes les notifications visibles livrées par iOS lorsqu'il est suspendu.

Si un événement manque, exporter après l'essai `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`, avec les heures et le type de chaque envoi. Garder également `snapnotify.log.1` si la session a été répartie par rotation. Ne pas fournir de mot de passe, jeton APNs complet, profil de signature ni contenu privé de conversation.

## En cas de doublons ou de gêne

Le nouveau repli peut relayer une notification interne non classable par type. Pour isoler son effet, mettre `NativeNotificationBridge=false` dans `Documents/SnapNotifyConfig.plist` et relancer manuellement l'application. Les réceptions structurées restent actives.

Pour isoler un problème audio/batterie, mettre `ExperimentalKeepAlive=false`, en tenant compte du fait que le comportement arrière-plan peut alors changer. Ne pas activer de nouveaux modes d'arrière-plan ou changer de signature au milieu d'un essai comparatif sans le noter.
