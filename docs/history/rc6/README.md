# SnapNotify 4.0.0-rc6

Correctifs pour Snapchat **14.17.1**, destiné à être injecté dans l’IPA puis signé avec Sideloadly. Appareil cible déclaré : iPhone 14, iOS 26.6.2. La compatibilité sur cet appareil reste à vérifier.

**Archive de sources, sans IPA et sans dylib compilée.** Le cœur C est testé sous Windows. La compilation iOS et les six programmes Foundation doivent réussir sur Mac/Xcode ou via le workflow inclus avant installation.

## Changements

- Vocaux reconnus via les prédicats natifs et les types symboliques, avec le texte « t’a envoyé un vocal ». Les chats, snaps, médias de chat, stickers, partages et réponses aux stories restent reconnus lorsque Snapchat fournit un type explicite. Les accusés de lecture, suppressions et autres événements de contrôle ne deviennent pas de faux messages. Aucun enum numérique supplémentaire n’est deviné.
- File FIFO commune aux événements et aux notifications natives : jusqu’à 8192 éléments en attente, 16 envois en cours. Les rafales ne réservent plus tous les tickets de déduplication simultanément. Les identifiants de requêtes séparent aussi les changements de compte.
- Cache d’identifiants expirant : la limite de 2048 identifiants par conversation ne bloque plus définitivement la réception. Les métadonnées arrivant en plusieurs callbacks ne font plus perdre automatiquement un message.
- Prise en charge du vrai délégué de notifications, même si Snapchat le remplace ou hérite de son implémentation. Le réglage `NotifyInForeground` vaut désormais `true` pour les nouvelles configurations.
- Un simple callback d’état d’appel ne coupe plus le lecteur de maintien en arrière-plan. Après une interruption audio, une reprise n’est tentée que si iOS indique `ShouldResume`; une catégorie enregistrement/appel reste protégée.
- Diagnostics enrichis : état audio, mode audio déclaré, permissions, interruption, durée en arrière-plan, intervalle entre passages du thread principal, dernière réception, file restante et échecs.

## Compiler et installer

1. Copier le projet complet dans un dépôt, y compris `.github`, `Sources`, `Core`, `tests` et `scripts`.
2. Lancer **SnapNotify tests and build**. Le workflow exécute les tests portables, les **six** programmes Foundation puis compile la bibliothèque iOS arm64.
3. Télécharger **SnapNotify-v4-dylib** provenant de cette nouvelle exécution. L’artefact contient `SnapNotify.dylib` et son empreinte SHA-256.
4. Remplacer l’ancienne bibliothèque dans la procédure d’injection Sideloadly, puis signer/réinstaller l’IPA. Ne pas cumuler plusieurs copies de SnapNotify. Vérifier `READY version=4.0.0-rc6 host=14.17.1` dans le journal après lancement.

Sur Mac avec Xcode : `make test`, `make test-macos`, puis `make`. Le chemin Theos reste disponible.

**Une configuration déjà présente dans `Documents/SnapNotifyConfig.plist` est conservée.** Pour avoir les notifications quand Snapchat est ouvert, passer sa clé `NotifyInForeground` à `true`. Copier aveuglément le fichier exemple écraserait les alias et préférences : modifier uniquement la clé voulue. `ExperimentalKeepAlive` conserve sa valeur existante.

## L’arrêt après environ dix minutes

Les coupures provoquées par des callbacks idle sont corrigées. Cela ne prouve pas que c’était la cause unique sur cet iPhone. Le maintien audio reste expérimental : il ne rouvre pas automatiquement une connexion Snapchat fermée, ne recrée pas les droits APNs et ne garantit pas que le processus reste actif.

La présence de la carte Snapchat dans le sélecteur d’apps ne signifie pas que le processus exécute encore son code. iOS peut suspendre l’application; sans réception effective, le tweak ne peut pas créer une notification pour un nouveau message. Voir [Apple : temps d’exécution en arrière-plan](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) et [notifications locales](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

Les notifications déjà confiées à iOS restent gérées par iOS. Une requête acceptée n’est pas la preuve qu’une bannière a été montrée individuellement : permissions, regroupement et modes de concentration interviennent.

## Vérifier sur l’iPhone

Suivre [le protocole appareil](docs/VALIDATION_IPHONE.md), avec une rafale de messages et des essais à 1, 5, 10, 15 et 30 minutes en arrière-plan. En cas de coupure, conserver `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json` avant et après le retour dans Snapchat. Aucun contenu de message n’est exporté dans ces diagnostics.

Les vérifications de rc6 et les tests précédemment exécutés sur rc5 sont détaillés dans [TESTS_EFFECTUES](docs/TESTS_EFFECTUES.md) et `VALIDATION.json`. Les documents rc4 et `docs/history` décrivent les livraisons précédentes.
