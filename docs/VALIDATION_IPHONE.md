# Essai sur l'iPhone — rc5

Vérifier `READY version=4.0.0-rc5` après remplacement de la bibliothèque et re-signature de l'IPA. Ouvrir la liste des amis et la conversation du compte de test, puis quitter le premier plan sans fermer la carte de l'app.

## Types et rafale

Envoyer depuis le second compte un vocal, un chat, un snap, une photo dans le chat, un sticker et un partage. Vérifier le nom et le libellé. Envoyer ensuite une série comptée (par exemple vingt chats, cinq vocaux, cinq snaps, trois stickers). Distinguer les bannières successives des éléments regroupés dans le centre de notifications. Les appels et la saisie ne doivent pas attendre la file de chats.

Une série de cinquante notifications peut prendre environ vingt secondes plus le temps de réponse de l'API avec l'espacement de 0,4 s. Ne pas conclure à une perte avant d'examiner les éléments en attente.

## Inactivité

Laisser Snapchat en arrière-plan et envoyer un snap/chat **sans saisie préalable** après deux, dix, quinze et trente minutes. Noter l'heure de chaque envoi. Refaire l'essai après une interruption audio, puis après une vraie réouverture de l'app. Il ne faut pas simuler une présence ou un appel pour obtenir un message.

## Lire l'état

`outbox.pending` : contenu reçu et admissible, en attente de soumission/réessai.

`outbox.accepted` : réponses positives de l'API conservées en file ; ce n'est pas un compteur de bannières vues.

`outbox.blocked` : autorisation/configuration bloque un élément, retenu jusqu'à réévaluation.

`outbox.heldForAccount` : ancien élément dont l'identité de compte ne peut pas être liée sans risque ; pas de livraison arbitraire.

`outbox.ioFailures` / `capacityFailures` : stockage ou limite de sécurité atteint. Pas de garantie de livraison illimitée.

`backgroundHealth.audioPlaying`, `audioInterrupted`, `duplexBackgroundDeferred`, `requiresUserResume` et `executionGaps` distinguent les états observés. Une lacune d'exécution peut être une suspension, un retard d'ordonnancement ou un changement d'heure : ce n'est pas un diagnostic définitif. Le fichier est une dernière photographie et cesse de changer si le processus est suspendu.

Conserver `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`, avec les horaires d'essai. Ne pas publier le répertoire `outbox-v5` : ses identifiants restent des métadonnées privées, même sans texte.
