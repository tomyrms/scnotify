# Essai rc2 avec les deux comptes

## Préparation

Construire la version complète et remplacer l'ancienne bibliothèque, puis re-signer l'IPA avec le processus déjà utilisé. Vérifier `READY version=4.0.0-rc2` et la version dans le JSON de statut. Conserver les réglages utilisateur opérationnels ; ne pas réinjecter deux dylibs. Activer le partage de fichiers dans l'outil de signature pour récupérer Documents si nécessaire.

Ouvrir la conversation du deuxième compte sur le compte récepteur, laisser charger son historique, puis passer en arrière-plan. Le chargement initial est volontairement silencieux et fournit une référence pour les observateurs de conversation. Les callbacks directs de réception n'exigent pas une notification de saisie préalable.

## Scénarios

| Action du compte émetteur | Attendu côté récepteur |
|---|---|
| Écrire puis arrêter sans envoyer | Saisie, pas de faux chat |
| Écrire puis envoyer un chat | Saisie puis notification de message distincte |
| Envoyer deux chats avec deux IDs différents | Deux événements de réception indépendants |
| Envoyer deux snaps sans écrire | Deux événements snap indépendants |
| Ouvrir, relire, sauvegarder ou supprimer un ancien chat | Pas de faux nouveau message |
| Quitter puis rouvrir la conversation | Pas de réannonce de l'historique |
| Reprendre la saisie après deux minutes | Nouvelle session de saisie, comme dans rc1 |
| Appeler puis raccrocher | Appel conservé, pas de faux message à la fin |
| Envoyer depuis le compte récepteur | Pas d'alerte de réception pour son propre envoi |

Une notification est conditionnée à un événement réellement observé et décodable. Pour un test au premier plan, régler temporairement `NotifyInForeground=true`, sinon la suppression des bannières au premier plan est normale. Revenir au réglage habituel après le test.

## Collecte

Noter l'ordre des actions et leurs heures. Après les essais, rouvrir Snapchat pour actualiser les rapports. Récupérer `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`. `snapnotify.log.1` est utile si le journal a tourné. Ces fichiers ne doivent pas être remplacés par le journal de compilation GitHub.

Le schéma ne contient pas les corps de messages : seulement les classes, champs/sélecteurs et les motifs de rejet. Garder `DiagnosticsIncludeIdentifiers=false` pour le partage courant. Les alias et `SelfUserID` sont des réglages personnels ; ne pas partager de certificat, token ou session de connexion.
