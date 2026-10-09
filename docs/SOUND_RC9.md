# Provenance et intégration du son

## Fichier fourni

- Archive utilisateur : `Iris_SnapNotify_v1.ipa`.
- Version de l’application : 14.17.1, identifiant `com.toyopagroup.picaboo`.
- Entrée extraite : `Payload/Snapchat.app/generic_push.mp3` (2 811 octets).
- SHA-256 source : `029c01210a6821a4b53615387b1f743fa90a79d7aaa6d4db9d69dbd52c448643`.
- La vérification statique ARM64 confirme que l’identifiant de son 0 sélectionne `generic_push.mp3` et le libellé « Default Sound ». `message_push_bf_sound.mp3` appartient à une branche conditionnée par l’option meilleurs amis et l’appartenance de l’expéditeur à cette liste. Ce choix repose donc sur le code de l’IPA, pas seulement sur les noms des fichiers. Le [rapport de provenance](sound-provenance-rc9.txt) contient les références précises et les limites de cette vérification.

## Conversion

Conversion locale avec ffmpeg, sans normalisation, changement de fréquence ou modification du nombre de canaux :

```sh
ffmpeg -hide_banner -loglevel error -nostdin -i generic_push.mp3 -map_metadata -1 -c:a pcm_s16le -bitexact snapnotify-snapchat.wav
```

WAV PCM 16 bits, stéréo, 44 100 Hz, 19 536 trames, 0,442993 seconde, 78 188 octets.

SHA-256 WAV : `4f34eac8c53d24d151daaa0185a8053d0ae875c652b92560021a2434e9a2f0db`.

Le fichier de référence est `Resources/SnapchatNotification.wav`. `scripts/embed_sound.py` produit `Sources/SNSnapchatSoundData.h`; `--check` vérifie leur correspondance. L’en-tête est livré prêt à compiler, donc ffmpeg n’est pas nécessaire pour construire la bibliothèque.

## Utilisation sur iPhone

Le module écrit atomiquement `snapnotify-snapchat-4f34eac8c53d.wav` dans `Library/Sounds` du conteneur de l’app. Un fichier identique est conservé et un fichier altéré est réparé. Sur iOS, la protection permet l’accès après le premier déverrouillage. Le choix est chargé avant les soumissions à `UNUserNotificationCenter`.

`UNNotificationSound soundNamed:` référence ce fichier. Selon [la documentation Apple](https://developer.apple.com/documentation/usernotifications/unnotificationsound), les sons personnalisés d’alerte doivent utiliser un format compatible, durer moins de 30 secondes et être placés dans le bundle ou `Library/Sounds`. Cette intégration utilise le format PCM documenté et ne lance aucun `AVAudioPlayer` supplémentaire.

Une erreur de fichier est exposée dans `snapnotify_status.json` sous `notificationSound`, avec `requested`, `effective`, `ready`, `errorDomain` et `errorCode`. Le repli sur le son système préserve l’alerte, mais n’est pas présenté comme une installation réussie du son Snapchat.
