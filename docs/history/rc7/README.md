# SnapNotify 4.0.0-rc7 — saisie et vocal distincts

Sources à compiler, puis à injecter et signer avec Sideloadly. Aucun IPA ni dylib précompilée dans cette archive. Cible : Snapchat 14.17.1; appareil déclaré : iPhone 14, iOS 26.6.2.

## Deux activités, deux libellés

- Composition texte reconnue : **« est en train d’écrire… »**.
- Activité vocale reconnue : **« est en train d’enregistrer un vocal… »**.
- Vocal effectivement reçu : **« t’a envoyé un vocal »**, inchangé.

rc7 décode l’état du paquet duplex `presence`, que les anciennes versions ignoraient. La distinction utilise le drapeau de composition et le drapeau vocal du protocole, documentés dans une implémentation publique indépendante. Elle ne déduit pas un vocal du temps passé à écrire et n’interprète pas arbitrairement les valeurs numériques `typingState` du modèle iOS.

Un changement texte → vocal, même avec un bref arrêt intermédiaire, réarme la notification et annule une éventuelle ancienne notification encore en attente. Les conversations sont traitées séparément. Les paquets invalides ne changent aucun état.

**Limite à connaître :** si l’événement de présence détaillé n’arrive pas ou n’est pas compatible, le type reste inconnu et la notification de préparation attend un état identifiable. Les notifications de messages reçus continuent à fonctionner. Le code public nomme le drapeau `speaking`; son interprétation comme enregistrement vocal dans cette version iOS reste à confirmer sur l’iPhone.

Les données sont limitées à Snapchat 14.17.1 et à des paquets structurés validés. Les états précis expirent après 15 secondes. Le propre compte est exclu quand son ID est connu; sinon il faut que le récepteur natif ait déjà identifié le participant comme distant.

## Installation

1. Copier le projet complet, y compris `.github`, `Sources`, `Core`, `tests` et `scripts`, dans le dépôt utilisé pour compiler rc5.
2. Lancer **SnapNotify tests and build**. Attendre la réussite des tests portables, des **sept** programmes Foundation et du build iOS arm64.
3. Récupérer le nouvel artefact **SnapNotify-v4-dylib**, remplacer l’ancienne bibliothèque dans la procédure Sideloadly, puis signer/réinstaller.
4. Vérifier `READY version=4.0.0-rc7 host=14.17.1` dans `snapnotify.log`.

Sur Mac/Xcode : `make test`, `make test-macos`, `make`. Les réglages existants sont conservés. Pour les notifications au premier plan, la clé `NotifyInForeground` de `Documents/SnapNotifyConfig.plist` doit être `true`.

## Validation

**115 tests C/Python réussis**, dont 21 pour le nouveau décodeur. Son fuzzer a exécuté **100 000 entrées** avec UBSan. Les sept tests Foundation et la compilation iOS n’ont pas été exécutés sur cet hôte Windows. Aucun essai rc7 sur iPhone n’est revendiqué.

Voir [les tests](docs/TESTS_EFFECTUES.md), [le protocole iPhone](docs/VALIDATION_IPHONE.md) et [la source du schéma](docs/SOURCES_RC7.md).

La file d’attente, les notifications de messages reçus et le maintien en arrière-plan de rc5 sont conservés. Le maintien audio reste expérimental et ne garantit pas l’exécution permanente ni la reconnexion du canal Snapchat. Les documents `docs/history` décrivent les versions précédentes.
