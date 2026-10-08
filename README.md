# SnapNotify 4.0.0-rc5 — vocaux, rafales et reprise

Base : `tomyrms/scnotify`, commit `6692b9fe72764d6246174c93eac03348d9e45116` (rc4), dont l'utilisateur confirme le fonctionnement des chats, snaps, appels et saisies. Cette version conserve le décodeur des appels, les transitions de saisie et le correctif de réception natif 14.17.1.

## Ce qui change

Les messages vocaux reconnus portent le texte « NOM t’a envoyé un message vocal ». Les photos de chat, les autres médias de chat, les stickers/Bitmoji, les partages, les réponses aux stories et les positions explicitement typées disposent de textes adaptés. La nature est déduite des getters natifs et des types symboliques, pas des mots présents dans une conversation. Une vidéo dont le modèle ne précise pas davantage la nature est annoncée comme un média, pas arbitrairement comme une photo. Les réactions, suppressions et accusés de lecture restent des événements de contrôle, pas de nouvelles réceptions.

Les chats/snaps éligibles vont dans une file persistante `Application Support/SnapNotify/outbox-v5`. Chaque message a son propre identifiant de notification ; un deuxième message du même expéditeur n'écrase pas le premier. Le sous-type ne change pas la clé de déduplication. Les notifications de contenu sont soumises une par une, avec un espacement minimal de 0,4 seconde après la réponse à la soumission précédente. Appels et saisie gardent leur chemin immédiat et ne sont pas mis derrière la file de contenu.

Les callbacks connus de grands lots sont traités par paquets de 128, plutôt que tronqués par la limite de 256 du décodeur élémentaire. Lorsque 64 lots attendent déjà le traitement, le callback subit une contre-pression synchrone au lieu de jeter ses données structurées. Cela peut ralentir brièvement l'hôte sous charge extrême. Le cache de messages vus n'arrête plus toute nouvelle réception une fois rempli : il conserve une fenêtre tournante de 8192 identifiants. La file persistante garde aussi les succès de soumission pendant 24 h pour la déduplication.

## Le problème après environ dix minutes

Il n'y avait pas de minuterie d'arrêt fixe à dix minutes dans rc4. En revanche, la preuve qu'un utilisateur est distant dépendait de l'état temporaire de saisie/présence, supprimé après quelques minutes. Quand le compte local n'était pas encore connu, cela pouvait de nouveau rendre indéterminé le sens entrant d'un snap/chat. rc5 conserve séparément cette preuve pour le même utilisateur et la même conversation (24 h, cache limité), et l'efface à un changement de compte détecté.

La reprise au premier plan réinitialise un ancien état d'interruption audio : iOS n'envoie pas nécessairement une fin d'interruption. Une simple mise à jour de l'état d'appel ne coupe plus le maintien audio ; il est arrêté lorsque la catégorie audio indique effectivement une utilisation du micro/appel. Un arrêt imprévu du lecteur peut faire l'objet de deux tentatives limitées de reprise, seulement lorsque l'état audio et l'arrière-plan le permettent. Le contrôleur ne simule jamais une transition de l'app au premier plan et n'invente aucune connexion réseau. Si la transition d'arrière-plan native a été transmise, `requiresUserResume` le signale.

**Cette correction ne garantit ni une exécution permanente ni des notifications reçues pendant qu'iOS a suspendu/terminé le processus.** Un timer du mod ne peut pas réveiller un processus suspendu. Les diagnostics distinguent absence d'événements réseau, état du lecteur et grand intervalle entre passages du contrôle ; un grand intervalle ne prouve pas, à lui seul, une suspension.

## Installer

La bibliothèque précompilée validée est incluse dans `prebuilt/SnapNotify.dylib`, avec son SHA-256 et les empreintes des 32 fichiers de code/tests correspondants. Le run de validation est `37852967825` ; les détails figurent dans `docs/TESTS_EFFECTUES.md`. Aucun IPA signé n’est inclus.

Utiliser la bibliothèque de l'artefact rc5 validé, ou copier la totalité de ce projet puis lancer `SnapNotify tests and build`. Le projet livré n'a pas besoin des fichiers techniques `.ci` de la branche de validation : ses sources sont déjà modifiées. Les tests macOS précèdent la compilation arm64 et bloquent la publication en cas d'échec.

Remplacer l'ancienne bibliothèque dans l'IPA, refaire l'injection/signature habituelle, puis vérifier `READY version=4.0.0-rc5`. Ne pas injecter plusieurs versions à la fois. L'IPA complet n'est pas fourni et sa signature n'est pas réparée par ce projet.

## Réglages

Les nouvelles clés sont activées par défaut même si une ancienne configuration ne les contient pas : `VoiceNotifications`, `MediaNotifications`, `StickerNotifications`, `ShareNotifications`. `MessageNotifications` reste l'interrupteur général des contenus du chat. `NotificationSpacingSeconds` vaut 0.4 (bornes : 0.05 à 2). `ExperimentalKeepAlive` reste conforme à la base utilisée : activé par défaut, désactivable dans `Documents/SnapNotifyConfig.plist`.

Une notification acceptée par l'API iOS n'est pas une garantie de bannière visible. L'affichage dépend notamment du regroupement, du résumé programmé, de Concentration et des réglages d'alertes. Choisir l'affichage « Liste », désactiver le regroupement pour Snapchat et vérifier ses autorisations pour examiner séparément les éléments, sans confondre une pile avec une perte.

## Données et limites de la file

La file n'enregistre ni texte de chat, ni enregistrement vocal, ni nom, ni jeton : uniquement les identifiants nécessaires, le sous-type et les états de soumission. Ce sont quand même des métadonnées privées, stockées avec la protection iOS jusqu'au premier déverrouillage. Ne pas publier ce répertoire.

Après une erreur temporaire, l'élément est conservé et réessayé avec le même identifiant et un délai croissant. Après un refus d'autorisation, il reste bloqué jusqu'à la prochaine reprise/réévaluation ; le mod n'essaie pas de contourner le refus. Un manque de réponse pendant 15 secondes libère la file pour les autres éléments, sans effacer le message. Un retour au premier plan ne supprime pas les messages déjà mis en attente en arrière-plan.

La restauration après relancement n'envoie que les éléments liés à une identité de compte vérifiée, ou à la session courante. Un élément enregistré lors d'une ancienne session dont le compte était inconnu reste retenu, plutôt que risquer de l'afficher sur un autre compte. Un changement de compte identifié purge les éléments du précédent compte.

Limite de sécurité : 20 000 entrées persistantes ; aucun élément pending n'est évincé pour faire de la place. Une saturation ou une erreur disque est signalée ; en cas d'erreur disque, l'élément nouvellement reçu reste en mémoire si possible. Le dispositif n'est pas une garantie de livraison illimitée. Une mort du processus exactement entre acceptation iOS et enregistrement du succès peut provoquer une resoumission au redémarrage, avec le même identifiant. L'absence d'un élément du centre de notifications n'est jamais utilisée pour le republier : il a pu être effacé par l'utilisateur.

## Validation sur appareil

Faire une rafale de 20 chats, 5 vocaux, 5 snaps et 3 stickers depuis le second compte ; noter les quantités. Laisser ensuite l'app en arrière-plan, sans la fermer, puis envoyer un snap sans activité de saisie préalable après 2, 10, 15 et 30 minutes. Refaire un appel et un vocal après une interruption audio. Les quantités sont un protocole proposé, pas des tests déjà exécutés ici.

Les éléments utiles sont `outbox.pending`, `outbox.accepted`, `outbox.blocked`, `outbox.heldForAccount`, `receiveBackpressureWaits` et `backgroundHealth` dans `snapnotify_status.json`, avec le journal et le schéma habituels. Les résultats effectivement exécutés figurent dans `docs/TESTS_EFFECTUES.md`.
