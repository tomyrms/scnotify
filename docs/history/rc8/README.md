# SnapNotify 4.0.0-rc8 — messages rapprochés et confirmations tardives

Sources à compiler, puis à injecter et signer avec Sideloadly. Aucun IPA ni dylib précompilée dans cette archive. Cible : Snapchat 14.17.1; appareil déclaré : iPhone 14, iOS 26.6.2.

## Corrections

- **Métadonnées retardées :** un chat récent ne devient plus trop ancien simplement parce que son callback ou son décodage arrive après celui d’un vocal. Le seuil de création reste fixé au début de la surveillance. Le contrôle de fraîcheur de cinq minutes et le rejet de l’historique initial sont conservés.
- **Copies partielles d’un message :** une représentation complète peut fournir la date, la direction entrante, le nom et le type vocal manquants à une autre copie du même message, dans le même callback. Des dates contradictoires empêchent cette fusion.
- **Confirmations tardives d’iOS :** un délai de réponse supérieur à 15 secondes libère la place dans la file, sans retirer une notification de message ou de snap qui a pu être acceptée entre-temps. Le résultat tardif reste traité. Un délai dépassé n’entraîne pas de renvoi automatique; la réservation anti-doublon dure jusqu’à cinq minutes pendant l’incertitude.
- **Alertes natives identiques :** deux objets de notification distincts peuvent produire deux alertes, même avec un titre et un texte identiques. Les callbacks multiples du même objet restent regroupés brièvement.
- **Relance et annulation :** une ancienne échéance ne peut plus bloquer la deuxième tentative; une retransmission n’écrase plus une demande déjà en cours. L’annulation de la saisie ou d’un appel reste indépendante des chats reçus.

Les deux états « est en train d’écrire… » et « est en train d’enregistrer un vocal… » sont conservés, ainsi que « t’a envoyé un vocal ». Voir [la provenance et les limites du schéma de présence](docs/SOURCES_RC7.md).

## Installation

1. Remplacer les sources du projet de compilation par le contenu complet de cette archive, y compris `Core`, `Sources`, `tests`, `scripts` et `.github`.
2. Lancer **SnapNotify tests and build**. Attendre les tests portables, les sept programmes Foundation et la compilation iOS arm64.
3. Récupérer **SnapNotify-v4-dylib**, remplacer la bibliothèque dans la procédure Sideloadly, puis signer/réinstaller.
4. Vérifier `READY version=4.0.0-rc8 host=14.17.1` dans `snapnotify.log`.

Sur Mac avec Xcode : `make test`, `make test-macos`, `make`. Les réglages existants sont conservés. Pour les alertes quand Snapchat est ouvert, `NotifyInForeground` doit être `true` dans `Documents/SnapNotifyConfig.plist`.

## Son

SnapNotify utilise le son par défaut d’iOS (`UNNotificationSound.defaultSound`). Pour le changer sur iPhone : **Réglages → Sons et vibrations → Alertes par défaut**. Cela concerne aussi les autres apps utilisant ce son système. Cette version n’ajoute pas de sélecteur de son propre à SnapNotify.

Référence : [Apple — UNNotificationSound](https://developer.apple.com/documentation/usernotifications/unnotificationsound).

## Validation et limites

**140 tests C/Python réussis** sur Windows avec compilation du C de production. Ils incluent une rafale de 2 048 identités et les transitions de livraison, avec succès tardif, erreur tardive et relance. Voir [les vérifications](docs/TESTS_EFFECTUES.md).

**Non exécutés ici :** les sept programmes Foundation, la compilation iOS et l’essai sur iPhone. La perte rapportée n’a pas été reproduite sur un appareil connecté; ces modifications corrigent des défauts vérifiés dans le code. [Le protocole iPhone](docs/VALIDATION_IPHONE.md) permet de vérifier le scénario vocal → arrière-plan → chat.

Le maintien en arrière-plan reste expérimental. Si Snapchat cesse de recevoir ses données ou si iOS suspend son processus, la file de notifications ne peut pas inventer les messages absents. Après utilisation du micro ou un appel, une catégorie audio `Record`/`PlayAndRecord` empêche toujours le lancement du maintien audio pour préserver la session de Snapchat. Une acceptation par iOS ne prouve pas l’affichage d’une bannière.

Les limites mémoire restent bornées; aucune promesse de volume illimité n’est faite. Sans ID natif, deux événements réutilisant exactement le même objet, le même texte et moins d’une seconde restent indiscernables. Les documents `docs/history` et journaux rc4/rc5/rc7 sont historiques.
