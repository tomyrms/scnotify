# Vérifications rc8

## Exécuté sur Windows

- **140 tests C/Python réussis**, sortie réelle dans `portable-tests-rc8.txt`. Python 3.12 et Zig 0.15.2, bibliothèques compilées à partir du code C de production avec avertissements traités comme erreurs.
- 56 tests du noyau, dont deux nouvelles régressions : vocal puis chat distinct avec arrêts de présence/appel intercalés; rafale de 2 048 identités, 16 réservations simultanées et confirmations inversées.
- 37 tests de réception, dont trois nouveaux tests du seuil stable malgré les observations tardives.
- 20 tests de la nouvelle machine de livraison : réception tardive après expiration, erreur tardive sans renvoi, une seule relance, annulation, confirmations répétées, indépendance de deux messages et échéances de tentatives obsolètes.
- 21 tests du décodeur de présence, six tests des outils IPA.
- Syntaxe des trois scripts shell vérifiée individuellement avec `bash -n`.
- Relecture croisée de l’intégration, incluant annulation, génération de compte, métadonnées contradictoires, expiration des réservations et réglages lors de la relance.
- Archive ZIP et manifeste SHA-256 vérifiés après génération.

## Non exécuté ici

Les sept programmes Objective-C/Foundation et la compilation iOS nécessitent macOS/Xcode. Des régressions ont été ajoutées à `TestReceive`, `TestNativeReceive` et `TestHostNotice` : elles couvrent les callbacks retardés, les copies partielles, les identités de bannières, les mutations et les accès concurrents, mais ne sont pas revendiquées comme exécutées.

Les tests C n’exécutent pas `UNUserNotificationCenter`, les hooks privés ou le cycle de vie de Snapchat. Aucun essai rc8 sur iPhone, mesure de batterie ou test réseau réel n’est revendiqué. Aucun nouveau fuzzing n’a été exécuté pour rc8; les journaux des versions précédentes restent historiques. La CI portable conserve ses fuzzers et sanitizers.
