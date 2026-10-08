# Analyse WGold / WhatsApp : comment il reçoit en permanence — et pourquoi Snapchat échoue

> Document d'analyse (08/10/2026) — base pour la suite de SnapNotify.
> Sources : WGold 3.4 (`wgold34`, bundle net.whatsapp.WhatsApp 26.38.74), WGoldPlus 26.37.73 (`wgoldplus`), Snapchat Iris 14.17.1 (`iris`), logs push SnapNotify.
> Méthode : analyse statique (Info.plist, entitlements, profils de signature, dépendances Mach-O, chaînes et symboles ObjC). Aucune exécution sur appareil.

---

## 1. Résumé exécutif (TL;DR)

1. **Le différenciateur n'est PAS le mode d'arrière-plan.** WhatsApp et Snapchat déclarent tous les deux des `UIBackgroundModes` comparables (`audio`, `fetch`, `processing`, `voip`, `location`, `remote-notification`…). Le plist n'explique rien.
2. **Le différenciateur est la signature.** La WGoldPlus 2.9 que tu as utilisée est signée avec un **profil de développement avec droit APNs (`aps-environment: production`)**, lié à l'UDID de ton iPhone. Résultat : **les vrais pushs Apple fonctionnent** pour cette app — c'est ça qui fait que WhatsApp « reçoit tout le temps », même écran verrouillé ou app fermée.
3. **Ton Snapchat sideloadé n'a jamais pu s'enregistrer aux pushs** : notre log SnapNotify le prouve (`PUSH REGISTRATION FAILED … aucune autorisation « aps-environment » valide détectée`). Sans push, pas de réveil, pas de notification en arrière-plan.
4. Le **WGold 3.4** (celui que nous venons de livrer) contient dans sa signature les entitlements d'origine de Meta (`aps-environment: production`, team `UKFA9XBX6K`) **mais aucun profil embarqué** : sideloadé avec Sideloadly, il perd le droit push. Pour le garder, il faut le re-signer via le même genre de service que la 2.9.
5. Le mod WGold en lui-même **n'ajoute aucun keep-alive magique** : c'est un mod de fonctionnalités (ghost mode, view-once, messages supprimés, avant/après…). Il embarque juste un outil « Fix socket » (efface le cache de routage et relance l'app).
6. **Pour SnapNotify, deux axes** : (A) obtenir une signature avec push pour Snapchat — c'est le vrai déblocage, le même que pour WhatsApp ; (B) porter la mécanique de rattrapage de WhatsApp (BGAppRefresh/BGProcessing/fetch + reconnexion + rattrapage) dans le tweak pour réduire au maximum la fenêtre sans notifications.

---

## 2. Fiche technique des binaires analysés

### 2.1 WGold 3.4 (base officielle WhatsApp 26.38.74)

| Élément | Valeur |
|---|---|
| Bundle | `net.whatsapp.WhatsApp` |
| Version | 26.38.74 (build 1077478047), MinOS 15.1 |
| `UIBackgroundModes` | `bluetooth-peripheral, bluetooth-central, audio, fetch, location, processing, remote-notification, voip` |
| Frameworks embarqués | `SharedModules`, `CommonLibrary`, `PsiphonTunnel` (contournement réseau/proxy), `CydiaSubstrate`, `WGold.dylib` + `WGold.bundle` |
| Injection du mod | Commande de chargement `@rpath/WGold.dylib` dans le binaire principal (fonctionne aussi sideloadé) |
| Extensions | `NotificationExtension` (content-extension), `ServiceExtension` (service), `Intents`, `Widget`, `Share`, `BroadcastUpload` |
| Fichier notable | `cyan.entitlements` à la racine du bundle (voir §3) |
| Profil embarqué | **Aucun** (`embedded.mobileprovision` absent) |

Entitlements observés dans la signature (copie des entitlements d'origine Meta) :

```
application-identifier   = UKFA9XBX6K.net.whatsapp.WhatsApp
aps-environment          = production
com.apple.developer.pushkit.unrestricted-voip = true
com.apple.developer.messaging-app              = true
com.apple.developer.calling-app                = true
com.apple.developer.carplay-messaging / carplay-communication = true
com.apple.developer.siri                       = true
application-groups       = group.net.whatsapp.* (7 groupes)
```

### 2.2 WGoldPlus 26.37.73 (l'IPA « qui marche »)

| Élément | Valeur |
|---|---|
| Profil embarqué | **Oui** — `embedded.mobileprovision` (19 Ko) |
| Nom du profil | `00008101-001345081ADA601E2QA420` (profil lié à un appareil) |
| Équipe signataire | TeamName « xi si », TeamIdentifier `L6N24SV5R3` (équipe tierce, ce n'est pas Meta) |
| App ID du profil | `L6N24SV5R3.app.walnut1118.quartz7798` (App ID leur appartenant) |
| Appareil autorisé | `00008101-001345081ADA601E` — **un seul UDID : le tien** (profil créé pour ton appareil) |
| `aps-environment` | **`production`** |
| `get-task-allow` | `false` |
| Validité | créé le 2026-03-11, **expire le 2027-03-11** |

**C'est le point clé de tout ce document.** Ce profil est un profil Apple **valide**, émis pour une équipe qui possède un App ID avec la capacité « Push Notifications », et enregistré pour l'UDID de ton iPhone. L'application signée avec ce profil a donc le **droit APNs complet** : elle s'enregistre, reçoit un token, et les serveurs de WhatsApp (Meta) poussent dessus. La dissemblance entre l'App ID du profil (`…walnut1118.quartz7798`) et le bundle réel (`net.whatsapp.WhatsApp`) n'empêche pas la livraison — c'est le montage classique des « certificats push » vendus par les services de signature.

### 2.3 Snapchat Iris 14.17.1 (le sideload qui échoue)

| Élément | Valeur |
|---|---|
| Bundle | `com.toyopagroup.picaboo` |
| `UIBackgroundModes` | `audio, bluetooth-central, external-accessory, fetch, location, processing, remote-notification, voip` — **autant que WhatsApp** |
| Signature actuelle | Sideloadly (compte perso) → **pas d'`aps-environment` valide** (log SnapNotify à l'appui) |

---

## 3. Pourquoi WhatsApp « reçoit tout le temps » — les 3 mécanismes combinés

Les notifications WhatsApp fiables = **push Apple (déclencheur) + arsenal d'arrière-plan (capacité) + notifications locales (affichage)**.

### 3.1 Le canal permanent XMPP (le « socket »)

WhatsApp ne récupère pas les messages par HTTP à la demande : il garde un **flux XMPP persistant** avec les serveurs Meta.

Symboles relevés dans le binaire principal :

- Classes : `XMPPConnection`, `XMPPConnectionMain`, `XMPPConnectionHelping`, `XMPPConnectionState`, `XMPPConnectionStorageWorkerProviding(+Plugin)`, `XMPPConnectionLogoutHandlerPlugin`, `XMPPChatStorageProvidingPlugin`, `XMPPPresenceController(Main)`, `XMPPStreamWameta`.

Dans `SharedModules.framework` (le vrai cœur réseau, 70 Mo, 116 dépendances) on trouve la machinerie de keep-alive et de reconnexion :

- `keepAliveAndReturnError:`, `keepAliveTask`, `keepAliveInterval`, `keepAlivePingCount`, `lastKeepAliveSuccessTime`, `keepAliveShouldStop`, `KeepAliveDrainDiagnostics`, `useKeepAliveStreamOption`
- Raisons de reconnexion : `PingReconnect`, `ErrorReconnect`, `Reconnect`
- `WAConnectionQueue`, `reportXmppBackgroundFetchEvent`, `XMPPDirectConnectionFeature`
- Écritures réseau protégées par tâches d'arrière-plan : `performWriteBlockWithBackgroundTaskWithConnection:block:error:`, `shouldUseConnectionQueueBackgroundTask`, `beginBackgroundTaskWithName:forced:expirationHandler:`

**Lecture** : connexion TCP longue durée + pings à intervalle + compteur de pings + reconnexion automatique sur échec de ping. Tant que le processus tourne, les messages arrivent en temps réel (faible latence). Aucun padding magique : c'est du XMPP classique, bien exécuté.

### 3.2 Les réveils système (quand le processus ne tourne plus)

Quand iOS suspend l'app (≈30 s après le passage en arrière-plan), le socket meurt. WhatsApp compte alors sur :

- **Pushs silencieux** (`content-available`) : `didReceiveRemoteNotification:fetchCompletionHandler:`, `silentPushNotifCode`, `silentPushNotifRegCode:iosDeviceRegistrationUUID:…` — le push réveille l'app quelques secondes, elle se reconnecte et télécharge le delta.
- **Pushs visibles** : le popup lui-même est poussé par Meta (avec la service-extension `ServiceExtension` qui déchiffre/modifie le contenu E2E avant livraison), pendant que l'app se réveille pour synchroniser.
- **VoIP PushKit** (appels) : `PKPushRegistry`, `PKPushCredentials`, `PKPushPayload`, `PKPushTypeVoIP`, `parse_voip_push_payload`, `hasValidVOIPToken`, entitlement `pushkit.unrestricted-voip` — les pushs VoIP ont un statut privilégié (réveil quasi garanti, exécution immédiate).
- **Background fetch / BGTask (filet de sécurité)** : `performFetchWithCompletionHandler:`, `WABackgroundAppRefreshTask`, `WABackgroundFetchTask`, `BGAppRefreshTaskRequest`, `BGProcessingTaskRequest`, `earliestBeginDate`, `requestForBackgroundAppRefreshTask:` + framework `BackgroundTasks` lié. iOS réveille périodiquement l'app (opportuniste, minutes→heures) même sans push ; l'app en profite pour se reconnecter et rattraper.

### 3.3 L'affichage : notifications locales générées par l'app

WhatsApp déchiffre localement et stocke le message, puis **poste lui-même une notification locale** (`WANotificationsMain`, `WANotificationsShared`, `WANotificationSuppression`, `WAMessageNotificationBehavior`, `UNUserNotificationCenter`+`addNotificationRequest:`). C'est pour ça que le contenu exact s'affiche : il est déchiffré sur l'appareil. Les pushs servent surtout de signal de réveil, pas de transport du texte.

**Conséquence pratique** : du moment que l'app est réveillée (par n'importe quel moyen), tu reçois ta notification. C'est un pipeline « push → réveil → socket → décryptage → notif locale ».

### 3.4 Le mod WGold proprement dit

Analyse des chaînes du dylib (1,05 Mo, tweak Substrate, chargé par `@rpath`) :

- Fonctionnalités : Message Ghost Mode, ViewOnce Ghost/Dowload, Keep Deleted/Edited Messages, Unlimited Forward, Anti-suppression de statuts, Hide Blue Ticks/typing, Activity Notifications, waveform réelle pour notes vocales, voice changer, enregistrement d'appels, badges, etc.
- Il s'hooke principalement sur les **accusés de réception XMPP** (`sendViewReceiptsForMessagesIfNeeded:`, `sendPlayedReceiptsForMessages`, `revokeMessage:withInputs:`) pour les fonctions ghost/anti-delete.
- Il utilise `beginBackgroundTaskWithName:expirationHandler:` / `endBackgroundTask:` pour ses opérations (export, fichiers).
- « Fix hanging messages » : efface le cache de routage et le relance l'app (« This will clear connection routing cache files and forcefully close WhatsApp to refresh the Socket »).
- **Aucun keep-alive audio silencieux, aucun artifice de maintien forcé du processus** n'a été trouvé dans le mod. WGold n'a pas besoin de ça : le push fait le travail.

---

## 4. Le « process qui meurt » côté Snapchat — pourquoi c'est structurel

Snapchat, avec le même vocabulaire d'arrière-plan que WhatsApp, n'a **aucun réveil** sans push :

- Le duplex Snapchat en arrière-plan ne reçoit que des paquets `presence` (typing, présence) — vérifié dans nos logs v3/v4. Les messages/snaps n'y transitent pas.
- Les vraies notifications Snapchat sont émises **par ses serveurs via APNs** (contenu compris), pas générées localement par l'app.
- Sans `aps-environment` valide : pas de push → pas de réveil → pas de données → pas de notification. Notre keep-alive audio silencieux (SnapNotify) entretient le processus par intermittence, mais iOS finit toujours par : coupure audio (appel, autre app), suspension, terminaison.

Les deux causes distinctes de nos échecs précédents :

1. `applicationWillTerminate` doublement hooké → **crash** à chaque terminaison iOS (corrigé en v3.8) ;
2. absence de push → **aucun réveil structurel** (non corrigeable par un tweak).

---

## 5. Protocole de vérification sur ton iPhone (à faire une fois, 5 minutes)

**Test A — WhatsApp (valider que le push fonctionne sur ton installation pourtant sideloadée)**
1. Force-quit WhatsApp (swipe card up).
2. Téléphone verrouillé, attends 2 min.
3. Depuis un autre téléphone, envoie-toi un message WhatsApp.
4. Résultat attendu si push OK : notification visible en ≤10 s. (Si rien après ~15 min écran éteint, ton install actuelle n'a plus de push — probablement une re-signature Sideloadly qui a écrasé le profil.)

**Test B — Snapchat (valider l'absence de push)**
1. Force-quit Snapchat, verrouille, envoie un snap/message depuis ton 2e compte.
2. Attendu (état actuel) : rien. (Notre SnapNotify compense partiellement via son keepalive.)

**Test C — après re-signature push (voir §6-A)** : refaire B ; si la notif arrive app tuée, c'est gagné — Snapchat fonctionne nativement.

> Astuce : pour comparer scientifiquement, note l'heure d'envoi et l'heure de réception (téléphone A verrouillé, écran éteint) pour les deux apps sur 3 essais.

---

## 6. Plan pour SnapNotify

### A. Priorité n°1 — obtenir une signature avec push pour Snapchat (le vrai levier)

C'est exactement ce que la WGoldPlus utilise, et ça marche sur ton appareil. Trois pistes, par ordre de simplicité :

1. **Le service qui a signé ta WGoldPlus 2.9** (profil « xi si » / `L6N24SV5R3`, expiration 2027-03-11) : faire signer l'IPA Snapchat (avec SnapNotify injecté) par le même type de service à profil push lié à ton UDID. On garde tout le travail fait (injection + tweak), seule la signature change.
2. **Sideloadly + compte payant, option push** : Sideloadly sait demander un jeton push avec un compte payant ; notre échec précédent (message « aucune autorisation aps-environment ») indique que le droit n'était pas dans la signature. Vérifier la procédure/version Sideloadly « push notifications » et refaire le test A/B.
3. **Autre service de signature à « certificat push »** (type Signulous / ESign push) sur la même IPA.

Si (1/2/3) réussit : Snapchat reçoit ses vraies notifications **sans passer par notre socket**, app fermée comprise. SnapNotify reste alors un bonus : **noms** dans les notifications, **typing** par présence, statut en direct du canal duplex.

### B. Priorité n°2 — porter la mécanique de rattrapage de WhatsApp dans SnapNotify (sans push)

Tout est faisable dans le tweak actuel, sur le modèle exact de WhatsApp :

1. **Info.plist de l'IPA Snapchat** (nous le contrôlons au reconditionnement) : ajouter `BGTaskSchedulerPermittedIdentifiers` avec nos identifiants, garder `fetch` et `processing` (déjà présents) :
   ```xml
   <key>BGTaskSchedulerPermittedIdentifiers</key>
   <array>
     <string>ch.snapnotify.refresh</string>
     <string>ch.snapnotify.processing</string>
   </array>
   ```
2. **Enregistrer les tâches** au lancement (constructeur du tweak, avant la fin du launch) : `BGAppRefreshTaskRequest` (délai ~15 min) + `BGProcessingTaskRequest` (`requiresNetworkConnectivity = YES`).
3. **Handler d'exécution** (« rattrapage » calqué sur WhatsApp) :
   - laisser la reconnexion duplex se faire (le socket Snapchat se rétablit seul dès que le process tourne) ;
   - **déclencher la synchro delta** : le binaire Snapchat contient `performDeltaSync` et les classes `SCDeltaSync*` (déjà repérées) — à retrouver à l'exécution pour appeler la méthode (c'est le même rôle que la reprise WhatsApp) ;
   - laisser les hooks de réception (SNReceive) décoder ce qui arrive, poster les notifications (ledger déjà en place), puis **re-planifier** la tâche suivante + `setTaskCompleted`.
4. **Un seul mécanisme de fetch à la fois** : la seule présence de `BGTaskSchedulerPermittedIdentifiers` désactive le background fetch legacy (`application:performFetchWithCompletionHandler:`) sur iOS 13+. Choisir BGTaskScheduler (points 2–3) — ne pas combiner les deux.
5. **Limites honnêtes** : iOS accorde ces réveils de façon opportuniste (délai variable de quelques minutes à quelques heures, selon ton usage). Ce n'est **pas** de l'instantané comme un push — mais ça remplace le « jamais » par « rattrapage régulier », exactement le filet de sécurité de WhatsApp. Si l'utilisateur force-quit l'app, iOS peut suspendre ces tâches.
6. **Conserver** le keep-alive audio actuel (mode expérimental) : c'est la période où l'app reste éveillée et reçoit en temps réel (typing instantané).

### C. Ordre recommandé

1. Tester §5-A/B pour figer l'état réel de ton installation actuelle.
2. Lancer une signature push pour Snapchat (§6-A). C'est le seul chemin vers la parité avec WhatsApp.
3. En parallèle, j'implémente §6-B (BGTaskScheduler + rattrapage delta + fallback fetch) : ça améliorera aussi les installs sans push.

---

## 7. Annexes — index des preuves

### 7.1 Chaînes XMPP / connexion (binaire principal)
`XMPPConnection`, `XMPPConnectionMain`, `XMPPConnectionHelping`, `XMPPConnectionState`, `XMPPConnectionLogoutHandlerPlugin`, `XMPPChatStorageProvidingPlugin`, `XMPPConnectionStorageWorkerProviding(Plugin)`, `XMPPPresenceController(Main)`

### 7.2 Keep-alive / reconnexion (SharedModules)
`keepAliveAndReturnError:`, `keepAliveTask`, `keepAliveInterval`, `keepAlivePingCount`, `lastKeepAliveSuccessTime`, `keepAliveShouldStop`, `KeepAliveDrainDiagnostics`, `useKeepAliveStreamOption`, `PingReconnect`, `ErrorReconnect`, `WAConnectionQueue`, `reportXmppBackgroundFetchEvent`, `performWriteBlockWithBackgroundTaskWithConnection:block:error:`, `shouldUseConnectionQueueBackgroundTask`, `beginBackgroundTaskWithName:forced:expirationHandler:`

### 7.3 Réveils (binaire principal)
`performFetchWithCompletionHandler:`, `WABackgroundAppRefreshTask`, `WABackgroundFetchTask`, `BGAppRefreshTaskRequest`, `BGProcessingTaskRequest`, `earliestBeginDate`, `requestForBackgroundAppRefreshTask:`, `didReceiveRemoteNotification:fetchCompletionHandler:`, `content-available`, `silentPushNotifCode`, `PKPushRegistry`, `PKPushTypeVoIP`, `parse_voip_push_payload`, `hasValidVOIPToken`

### 7.4 Notifications locales (binaire principal)
`WANotificationsMain`, `WANotificationsShared`, `WANotificationSuppression`, `WAMessageNotificationBehavior`, `UNUserNotificationCenter`, `addNotificationRequest:withCompletionHandler:`

### 7.5 Extensions
`ServiceExtension` = `com.apple.usernotifications.service` (déchiffre/modifie la notification **avant** sa livraison — c'est le chemin du contenu E2E) ; `NotificationExtension` = `com.apple.usernotifications.content-extension` (interface personnalisée pour l'affichage de la notification déjà livrée).

### 7.6 Fichiers analysés
- `wgold34/Payload/WhatsApp.app` (extraction de `WGold_3.4.ipa`)
- `wgoldplus/Payload/WhatsApp.app` (extraction de `WhatsApp_WGoldPlus_-__v26.37.73_.ipa`)
- `iris/Payload/Snapchat.app` (Snapchat 14.17.1 + SnapNotify)
- Log SnapNotify `PUSH REGISTRATION FAILED` (install Snapchat Sideloadly)
