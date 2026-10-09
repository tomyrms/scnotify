# SnapNotify 4.0.0-rc9 — son Snapchat propre à l’app

Sources à compiler, puis à injecter avec Sideloadly. Cette archive contient le son extrait de l’IPA fournie et le code de SnapNotify; elle ne contient ni IPA modifiée ni bibliothèque précompilée.

## Son activé par défaut

Les notifications créées par SnapNotify utilisent désormais **le son `generic_push.mp3` extrait de ton IPA Snapchat 14.17.1**, converti en WAV PCM pour les alertes iOS. Il dure environ 0,443 seconde. Aucun réglage global de l’iPhone n’est modifié.

Le son est intégré dans la bibliothèque. Au lancement, SnapNotify installe automatiquement sa copie dans le dossier `Library/Sounds` de Snapchat avant de programmer des notifications. Il n’y a aucun fichier à copier manuellement sur l’iPhone. Les deux chemins de notifications, événements décodés et alertes natives relayées, utilisent ce choix.

L’option `NotificationSound` vaut `snapchat` par défaut, y compris si elle est absente d’un ancien fichier de configuration. Pour revenir au son système uniquement dans SnapNotify, définir cette clé sur `system` dans `Documents/SnapNotifyConfig.plist`, puis revenir dans Snapchat pour recharger les réglages.

Les correctifs rc8 concernant les messages rapprochés, les confirmations tardives d’iOS et les deux libellés texte/vocal sont conservés. Cette modification ne joue aucun son avec un lecteur audio et ne change pas la session audio utilisée par le maintien en arrière-plan.

## Installation

1. Copier le projet complet dans le dépôt de compilation : inclure `Sources/SNSnapchatSoundData.h`, `Sources/SNNotificationSound.m/.h`, `Resources`, `Core`, `tests`, `scripts` et `.github`.
2. Lancer **SnapNotify tests and build** et attendre les tests portables, les **huit** programmes Foundation et la compilation arm64.
3. Récupérer **SnapNotify-v4-dylib**, remplacer l’ancienne bibliothèque dans la procédure Sideloadly, puis signer/réinstaller.
4. Ouvrir Snapchat une fois. Vérifier `READY version=4.0.0-rc9` et `NOTIFICATION-SOUND requested=snapchat effective=snapchat ready=1` dans `snapnotify.log`.

Sur Mac avec Xcode : `make test`, `make test-macos`, `make`.

## Vérifications et limites

**143 tests C/Python réussis** ici, dont trois vérifications du fichier audio et des octets embarqués. Les huit tests Foundation et la compilation iOS n’ont pas été exécutés sur cet hôte Windows. L’écoute d’une vraie notification sur iPhone reste à vérifier.

Si l’installation du fichier sonore échoue, les alertes restent programmées avec le son système et le diagnostic l’indique explicitement. Les réglages Son/Silence/Concentration d’iOS continuent de s’appliquer.

Voir [la provenance du son](docs/SOUND_RC9.md), [les tests](docs/TESTS_EFFECTUES.md) et [l’essai iPhone](docs/VALIDATION_IPHONE.md). Les documents `docs/history` décrivent les versions précédentes. Le maintien en arrière-plan reste expérimental et ne garantit pas une connexion permanente à Snapchat.
