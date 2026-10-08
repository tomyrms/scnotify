# SnapNotify 4.0.0-rc1

Version candidate issue de l'audit du projet fourni (`87bc01f597134c3f9aa82f675f33a2823948ba7d`) et des trois journaux de test. Le projet reste une bibliothèque à injecter dans **ta propre installation de Snapchat**.

**Cette archive contient les sources et les tests, pas un IPA signé. Le cœur C a été exécuté et testé ; la compilation Xcode, les tests Foundation/macOS et le fonctionnement dans Snapchat sur iPhone restent à valider.**

## Ce qui change

Les appels sont décodés à partir du vrai paquet `volatile / CALLER_PUSH`, de son action `START` ou `STOP` et de son identifiant `callUuid`. Le mot `messageType` dans le JSON ne provoque plus une fausse notification de message. Un appel retransmis avec le même identifiant ne sonne pas une deuxième fois ; une fin d'appel n'est pas un nouvel appel.

La saisie et l'entrouverture utilisent des sessions indépendantes par conversation **et par utilisateur**. Un arrêt observé réarme la session. Une nouvelle activité après huit secondes sans mise à jour la réarme également, même si l'arrêt a été perdu. Une saisie continue ne produit pas une notification toutes les quinze secondes. Un arrêt annule une notification encore en attente de résolution du nom.

Les noms sont récupérés après le retour des méthodes de résolution, notamment `snapchatterForUserId:`. Les UUID objets sont normalisés, les noms Unicode conservés, les noms affichés préférés aux pseudonymes. Le cache ne mélange plus identifiants de conversation et identifiants de personne. Un nom absent n'est jamais inventé : le repli `Contact xxxxxxxx` signale explicitement un utilisateur non résolu.

Les réceptions de snaps/messages passent par des adaptateurs explicites de callbacks de réception et exigent un expéditeur, une conversation, un type reconnu et un identifiant de message. Deux snaps distincts ne se bloquent pas mutuellement. **Le déclenchement de ces callbacks n'est pas confirmé dans la version Snapchat utilisée pour les logs.** Les paquets inconnus sont diagnostiqués, pas transformés en fausses notifications.

## Construire sur GitHub Actions

1. Remplacer le contenu du dépôt par les fichiers de cette archive, **y compris `Core`, `Sources`, `tests`, `scripts` et `.github`**. Ne pas copier uniquement `Tweak.m`.
2. Lancer le workflow **SnapNotify tests and build**. Il exécute les tests C, les tests de mémoire, les tests Foundation et compile la bibliothèque avec le SDK Xcode du runner macOS.
3. Après réussite, récupérer l'artefact **SnapNotify-v4-dylib** : `SnapNotify.dylib` et sa somme SHA-256.
4. Remplacer l'ancienne bibliothèque dans ton processus d'injection/signature de l'IPA. Ne pas injecter simultanément v3 et v4, ni ajouter deux commandes de chargement pour la même bibliothèque. Réinstaller l'IPA avec ton outil habituel.

Le workflow n'a pas été exécuté à distance lors de la préparation de cette archive. Il bloque la publication de l'artefact si un test ou la compilation échoue.

### Sur un Mac équipé de Xcode

```sh
make test
make test-macos
make
```

Avec Theos déjà installé, le Makefile conserve ce chemin de build :

```sh
export THEOS=/chemin/vers/theos
make
```

## Premier essai sur l'iPhone

Ouvrir Snapchat, afficher la liste d'amis et le profil de ton compte de test pour donner aux résolveurs l'occasion de fournir les noms. Vérifier ensuite les fichiers du dossier Documents de l'application :

| Fichier | Utilité |
|---|---|
| `snapnotify.log` et `snapnotify.log.1` | Session courante et rotation précédente. |
| `snapnotify_status.json` | Nombre de paquets, noms connus et requêtes de notification acceptées. |
| `SnapNotifyConfig.plist` | Réglages créés au premier lancement, relus au retour au premier plan. |

`NOTIF-ACCEPTED` signifie que le système a accepté la requête locale, **pas qu'une bannière a nécessairement été montrée**. Les réglages iOS de notification restent applicables.

### Résolution des noms

Le cache v3 n'est pas importé, car il pouvait associer un titre de conversation à une personne. Si un nom n'est toujours pas disponible, rechercher `IDENTITY-LEARNED`, regarder `knownUsers` dans le statut et vérifier les hooks présents dans `SCAN`/`HOOK`.

Un alias manuel est possible en dernier recours dans `SnapNotifyConfig.plist` :

```xml
<key>Aliases</key>
<dict>
    <key>22222222-2222-4222-8222-222222222222</key>
    <string>Nom du compte de test</string>
</dict>
```

L'identifiant ci-dessus est fictif : utiliser l'identifiant réel du contact. `DiagnosticsIncludeIdentifiers=true` affiche les UUID complets dans le journal, uniquement pour ce diagnostic. Remettre ce réglage à `false` avant de partager les logs. `SelfUserID` permet de définir explicitement l'UUID du compte connecté si sa méthode de résolution n'est pas observable.

## Important : arrière-plan et signature

**Dans ce build, `ExperimentalKeepAlive` est activé par défaut** — sans lui, aucune notification ne peut arriver écran verrouillé (même mécanisme que le keepalive v3). La v3 changeait constamment la session audio de Snapchat, même au premier plan et après une interruption audio. Ce comportement pouvait interférer avec les appels et le micro ; il n'est plus imposé : l'expérience ne s'active qu'en arrière-plan, refuse d'écraser une session d'enregistrement/appel et s'arrête lors d'une interruption audio. Pour la désactiver, passer `ExperimentalKeepAlive` à `false` dans `SnapNotifyConfig.plist`.

Un mode de test est conservé : mettre `ExperimentalKeepAlive` à `true` dans le fichier de configuration, puis ramener l'application au premier plan et refaire le test. Il tente une boucle audio silencieuse uniquement en arrière-plan et, si le callback observé est exécuté sur le thread principal, diffère le passage en arrière-plan du composant Duplex. Il exige le mode `audio` dans `UIBackgroundModes`, refuse d'écraser une session d'enregistrement/appel et abandonne son maintien lors d'une interruption audio.

**Ce mode est expérimental, peut consommer de la batterie et n'est pas une garantie de connexion permanente.** Le laisser activé uniquement pour des essais contrôlés ; revenir à `false` si le micro, les appels, le son ou la stabilité se dégradent. Il ne ressuscite pas une application suspendue ou fermée de force et ne répare pas APNs.

Les logs fournis contiennent l'erreur APNs 3000 : l'enregistrement push échoue. Un entitlement `aps-environment` doit être autorisé par la signature/le profil ; l'ajouter simplement à `Info.plist` ou à du code ne suffit pas. Même un profil personnel autorisant APNs ne prouve pas que les serveurs Snapchat enverront leurs notifications vers cet identifiant d'application.

L'outil suivant vérifie en lecture seule les métadonnées utiles de ton IPA :

```sh
python3 scripts/inspect_ipa.py Snapchat.ipa
```

Sur macOS, il lit aussi les entitlements du binaire avec `codesign`. Sur les autres systèmes, il distingue explicitement les droits du profil de la signature non inspectée. Il ne modifie ni ne signe le fichier.

**Si plus aucun paquet n'arrive après le passage en arrière-plan, modifier encore l'anti-doublons ne suffira pas.** Le rapport de statut et le protocole ci-dessous permettent de distinguer absence d'événement, nom non résolu, refus de notification et suspension/arrêt du transport.

## Documents

- `docs/AUDIT_FR.md` : défauts identifiés, preuves et périmètre réel des corrections.
- `docs/TESTS_EFFECTUES.md` : tests réellement exécutés et vérifications restantes.
- `docs/VALIDATION_IPHONE.md` : essais à reproduire avec tes deux comptes.
- `docs/SOURCES.md` : documentation technique de référence.

Aucun log brut, token, certificat, identifiant réel de contact ou binaire Snapchat n'est inclus dans cette archive. Les trames de régression ont été anonymisées. Aucune fonctionnalité n'envoie ces données vers un serveur externe.
