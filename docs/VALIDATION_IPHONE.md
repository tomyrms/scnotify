# Essai iPhone rc9

1. Compiler et injecter rc9, puis ouvrir Snapchat après réinstallation pour installer le son embarqué.
2. Vérifier `READY version=4.0.0-rc9` et `NOTIFICATION-SOUND requested=snapchat effective=snapchat ready=1` dans `snapnotify.log`.
3. Désactiver le mode Silence pour l’essai et autoriser les sons de Snapchat dans les réglages de notifications iOS. Depuis un autre compte, envoyer un chat puis un vocal; écouter le son avec Snapchat ouvert puis en arrière-plan.
4. Refaire écran verrouillé après le premier déverrouillage de l’iPhone. Les alertes SnapNotify doivent conserver le son choisi.
5. Vérifier que le son des autres apps n’a pas changé. Le code ne modifie aucun réglage sonore global.
6. Pour tester le retour au comportement rc8, définir `NotificationSound` sur `system` dans `Documents/SnapNotifyConfig.plist`, puis revenir dans Snapchat. Remettre `snapchat` pour retrouver le son embarqué.
7. Refaire le scénario vocal → sortie de l’app → chat et les rafales du protocole rc8, conservé dans `docs/history/rc8/VALIDATION_IPHONE.md`.

Si le son système joue encore, lire `notificationSound` dans `snapnotify_status.json`. `effective=system` avec `ready=false` indique que l’installation locale du WAV a échoué; `errorDomain` et `errorCode` précisent le problème. Une notification acceptée par iOS ne prouve pas que le son était audible.
