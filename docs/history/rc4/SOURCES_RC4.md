# Sources et portée des preuves — rc4

## Données fournies dans cette conversation

- `snapnotify_receive_schema.json` : 15 callbacks Arroyo rejetés, modèle `SCNMessagingMessage`, type numérique 1 dans la dernière forme, getters disponibles, retour BOOL du présentateur non hooké et télémétrie Blizzard.
- `snapnotify_status.json` : rc3, 21 callbacks, aucun chat/snap décodé, six requêtes de notification acceptées, zéro perte de file/paquet, APNs non enregistré.
- `snapnotify(4).log` : rejets répétés alors que l'application est en arrière-plan ; version hôte 14.17.1, build14.17.1.0.

Les trois fichiers ne sont pas reproduits dans le ZIP. Leurs empreintes figurent dans `VALIDATION.json` pour identifier la base de l'analyse, sans publier leur contenu.

## Projet

Référence du code : https://github.com/tomyrms/scnotify/tree/092adc746dcd1b677bca7cb921c4736d7f318e25

Blobs critiques vérifiés : `Tweak.m` 406fff60bef9eded1a1b76adf806ca2bd8ace98e ; `Sources/SNRuntime.m` e12ddd7f731634a1562ab8fa186f1302383bb308 ; `Sources/SNReceive.m` 496ca39bfc5a37ba68f15e1ee97b1a28fbc904da. Les références de CI rc3 archivées ne valident pas le code rc4.

## Valeurs numériques : corroboration externe, pas preuve iPhone

https://github.com/0xzer/snapper/blob/d57f26881a58b94a4e14b541ce63b6930415e20e/protos/common.pb.go

Ce projet public rétro-conçu déclare `ContentType_SNAP = 0` et `ContentType_CHAT = 1`. Cela corrobore le repli limité, mais ne démontre pas que chaque version native de Snapchat expose le même enum. Le schéma fourni ne donne que la valeur 1, sans nom symbolique. Les prédicats du modèle natif sont donc préférés ; le repli est borné aux classes observées et à la version 14.17.1. Aucune valeur numérique de média, note, sticker ou contrôle supplémentaire n'est déduite de ce document.

Aucun code de protocole externe n'est copié ; aucun endpoint, jeton, authentifiant ou mécanisme d'accès au compte n'est ajouté.
