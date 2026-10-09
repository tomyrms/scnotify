# Validation iPhone rc7

Ce protocole reste à exécuter sur Snapchat 14.17.1.

1. Compiler et injecter rc7, lancer Snapchat et vérifier sa version dans `READY`. Autoriser les alertes iOS; activer `NotifyInForeground` pour l’essai avec Snapchat ouvert.
2. Depuis un autre compte, écrire un texte pendant quelques secondes : attendre « est en train d’écrire… ».
3. Arrêter, puis enregistrer un vocal : attendre « est en train d’enregistrer un vocal… ». Envoyer le vocal : vérifier séparément « t’a envoyé un vocal ».
4. Alterner texte → vocal et vocal → texte, avec et sans bref arrêt. Vérifier que l’ancien libellé en attente est annulé et que les répétitions du même état ne font pas une rafale de doublons.
5. Tester deux contacts/conversations, puis un groupe : la présence d’un contact ne doit pas attribuer son activité à un autre. Une mise à jour d’une conversation ne doit pas annuler l’activité d’une autre.
6. Refaire un essai en arrière-plan, puis la rafale de messages reçus et les essais de durée déjà utilisés avec rc5.

## Si aucune notification de préparation ne s’affiche

Consulter `snapnotify_status.json` :

- `presenceActivityPackets` doit augmenter lorsqu’un paquet de présence compatible est décodé.
- `presenceActivityRejected` indique un paquet incompatible ou malformé; aucun état n’est inventé dans ce cas.
- `compositionUnknown` indique que la présence générique a été vue sans pouvoir identifier texte/vocal. Le journal montre `PRESENCE-ACTIVITY-WAIT`.

Conserver `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`. Pour comparer les deux activités, noter l’heure d’un essai texte puis d’un essai vocal. Il faut ces observations pour valider le schéma sur cette IPA ou adapter sa réception si les paquets n’atteignent pas les hooks.

Une demande acceptée par iOS ne prouve pas qu’une bannière a été affichée. Le maintien en arrière-plan reste soumis à iOS; ce correctif porte sur la classification de l’activité.
