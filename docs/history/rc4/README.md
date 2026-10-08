# SnapNotify 4.0.0-rc4 — correctif ciblé du récepteur natif

**Sources à compiler, sans IPA ni `.dylib` précompilée.** Les tests C/Python ont été exécutés ici. Les nouveaux tests Foundation et la compilation iOS rc4 n'ont pas pu être lancés dans cette session ; ils doivent réussir sur le runner Mac avant installation. Ne pas utiliser un résultat de CI rc3 pour valider rc4.

## Pourquoi cette correction

Les trois diagnostics rc3 fournis montrent le vrai récepteur `SCArroyoConversationDataUpdateAnnouncer/onConversationUpdated:conversation:updatedMessages:removedMessages:` appelé 15 fois, mais zéro événement décodé : `unknown-content-type`. Son objet `SCNMessagingMessage` contient un `SCNMessagingMessageContent.contentType` numérique (`1` dans la dernière forme exportée), pas un enum symbolique GPB. Les rejets apparaissent aussi en arrière-plan. Cela confirme un blocage du décodeur ; ce n'est pas la preuve que chacun des callbacks représente un nouveau message différent.

Le correctif utilise d'abord les prédicats natifs du message (`isTextMessage`, `isChatMediaMessage`, etc.). Le repli numérique `0 → snap`, `1 → chat` est strictement limité au modèle `SCNMessagingMessage` / `SCNMessagingMessageContent` et à Snapchat **14.17.1**, la version du journal. La valeur d'un enum arbitraire ne déclenche jamais une notification. Cette correspondance limitée est corroborée par une source publique rétro-conçue, mais son fonctionnement sur ton appareil doit encore être vérifié.

## Changements

- Traitement distinct des messages mis à jour, de l'historique complet et des éléments supprimés dans le callback Arroyo à quatre arguments.
- Exclusion du récepteur analytique `SCNativeBlizzardLoggerDelegateImpl` : ses objets de métriques ne sont pas des messages.
- Lecture de `SCNMessagingUUID.toString`, des métadonnées de création et du sens entrant. Le sens peut provenir du compte local, d'un indicateur explicite de l'hôte ou du même participant distant déjà identifié dans la même conversation.
- Prise en charge des retours booléens `B` et `c` des hooks, notamment le présentateur de notifications refusé par rc3. La valeur originale de retour est préservée.
- Diagnostics des filtres de date/direction et de la connaissance du compte local, sans contenu de message exporté.

Les chemins des appels, de la saisie/entrouverture et de l'audio expérimental sont conservés. Aucun entitlement APNs, BGTask, faux réveil ou polling n'est ajouté. L'option `ExperimentalKeepAlive` existante reste inchangée et ne constitue pas une garantie d'exécution permanente.

## Compiler puis installer

1. Copier **tous les fichiers** de ce projet dans le dépôt, y compris `Sources`, `Core`, `tests`, `scripts` et `.github`. Ne pas copier uniquement `Tweak.m`.
2. Lancer le workflow **SnapNotify tests and build**. Attendre la réussite des tests portables, des **quatre** programmes Foundation et de la compilation iOS arm64.
3. Récupérer l'artefact **SnapNotify-v4-dylib** de cette nouvelle exécution, et non celui de rc3. Il contient `SnapNotify.dylib` et `SHA256SUMS.txt`.
4. Remplacer l'ancienne bibliothèque dans le processus d'injection/signature habituel et réinstaller. Ne pas empiler deux versions du tweak. Les réglages existants dans `Documents/SnapNotifyConfig.plist` restent prioritaires.
5. Ouvrir Snapchat et vérifier `READY version=4.0.0-rc4 host=14.17.1` dans le journal.

Sur un Mac avec Xcode : `make test`, `make test-macos`, puis `make`. Le Makefile garde aussi le chemin Theos existant.

## Vérification sur l'appareil

Ouvrir une fois le chat avec le compte de test, puis laisser Snapchat en arrière-plan sans fermer sa carte. Envoyer un chat après la saisie, puis deux snaps distincts. Les compteurs `decodedMessages` / `decodedSnaps` doivent progresser et le journal doit montrer `NOTIF-ACCEPTED type=message` / `type=snap`. L'acceptation de la requête par iOS ne prouve pas, à elle seule, qu'une bannière a été vue.

Les trois fichiers de diagnostic restent `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`. Les motifs après décodage sont maintenant visibles, notamment `snapshot-missing-time` ou `snapshot-direction-unknown` : aucun horodatage ou expéditeur n'est inventé pour contourner ces contrôles.

Détails : [correctif et limites](docs/CORRECTION_RC4.md), [tests réellement exécutés](docs/TESTS_EFFECTUES.md), [sources](docs/SOURCES_RC4.md). Les documents sous `docs/history` décrivent les anciennes versions, pas cette livraison.
