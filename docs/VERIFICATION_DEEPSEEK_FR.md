# Vérification de l'analyse WhatsApp / arrière-plan

Date : 8 octobre 2026. Document examiné : `ANALYSE_WHATSAPP_BACKGROUND.md`, transmis par l'utilisateur comme une recherche DeepSeek à vérifier. L'original reste inchangé. Les identifiants de profil et d'appareil qu'il contient ne sont pas recopiés dans cette livraison.

## 1. Résumé exécutif : deux problèmes distincts

**Observation dans les anciens logs fournis :** l'enregistrement APNs échoue avec le code 3000 et l'absence de droit `aps-environment` valide. Ce constat concerne ces installations/session anciennes ; il ne suffit pas à décrire l'état de la signature actuelle.

**Conclusion non démontrée dans la recherche :** la présence de ce droit dans un profil tiers expliquerait à elle seule les notifications WhatsApp et suffirait à rétablir celles de Snapchat. Apple décrit aussi la correspondance entre jeton, topic autorisé et environnement. Un profil possédant ce droit ne prouve donc pas que les serveurs du fournisseur puissent adresser cette installation. Ne pas acheter un service de signature sur cette seule promesse. [Apple : erreurs APNs](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns).

Le fonctionnement de la saisie et des appels rapporté par l'utilisateur montre, pour ces essais, qu'au moins certains événements parviennent au mod. Il faut aussi rechercher ce que le récepteur de messages ignore. Ce raisonnement ne garantit pas le maintien du processus toute la nuit.

## 2. Fiche technique des binaires : données rapportées, pas vérification reproduite

Le document énumère versions, profils, entitlements, classes et extensions de trois IPA. Ces binaires et les profils originaux ne sont pas joints à cette demande. Les valeurs sont donc traitées comme les relevés de l'auteur, non comme des faits que cette révision aurait vérifiés. La signature finale après réinstallation ne peut pas être déduite de la seule signature d'un IPA avant re-signature.

L'étiquette « profil de développement » est également trop précise à partir du seul droit APNs rapporté. Aucun profil ni certificat tiers n'a été ajouté au projet.

## 3. Mécanismes WhatsApp : hypothèses plausibles, chaîne causale non prouvée

Des noms `XMPPConnection`, `keepAliveTask` ou `WABackgroundAppRefreshTask` sont des pistes d'instrumentation. Leur présence ne prouve pas que ce chemin soit exécuté, qu'il reste actif en arrière-plan ou qu'il explique le comportement de WGold sur cet iPhone. L'absence de chaîne trouvée n'est pas non plus une preuve d'absence de fonctionnalité.

**Correction sur les réveils :** iOS peut suspendre le processus ; les mécanismes de rafraîchissement ne donnent pas de cadence garantie et peuvent ne pas lui accorder de temps. Le délai « environ 30 secondes » n'est pas une règle universelle de suspension. [Apple DTS : limites d'exécution](https://developer.apple.com/forums/thread/685525).

**Correction sur les extensions :** une extension de service peut modifier ou déchiffrer une notification avant livraison ; une extension de contenu sert à sa présentation. La répartition exacte dans les IPA cités doit être examinée, pas déduite de leurs seuls noms. [Apple : modifier et présenter les notifications](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/ModifyingNotifications.html).

## 4. Snapchat : « Duplex ne transporte que la présence » est injustifié

Le retour utilisateur et le décodage d'appels existant utilisent `volatile / CALLER_PUSH`. Les anciens logs montrent par ailleurs des enregistrements distincts pour `pcs`, `sync_trigger` et `hermod_dup`, avec notamment `SCHermodDuplexServiceImplementation` comme récepteur de ce dernier. Cela contredit une lecture limitée aux deux classes précédemment surveillées.

Ces observations **ne prouvent pas** que le contenu des chats ou des snaps soit transporté sur l'un de ces canaux. Elles justifient de suivre les récepteurs réellement enregistrés, d'inspecter les objets déjà décodés et de garder séparés « paquet reçu » et « événement de message validé ».

Un sélecteur de notification interne installé dans les vieux logs ne prouve pas non plus qu'il s'exécutera sur une nouvelle version. rc3 vérifie les signatures et ne notifie qu'en présence d'un contenu admissible.

## 5. Protocole de vérification : ne pas conclure d'un test négatif unique

Une notification manquante après fermeture forcée ne suffit pas à prouver que la signature est fautive. Le test doit distinguer application active, arrière-plan, verrouillage et fermeture forcée, et conserver les heures d'envoi/réception. Apple documente que la fermeture forcée empêche normalement la relance en arrière-plan jusqu'à un lancement manuel, avec des exceptions non documentées. [Apple DTS](https://developer.apple.com/forums/thread/685525).

Pour rc3, tester d'abord application laissée ouverte en arrière-plan. Le protocole détaillé est dans `VALIDATION_IPHONE.md`. La réception de données, leur décodage, l'acceptation d'une requête locale par iOS et l'apparition d'une bannière sont quatre résultats différents.

## 6. Plan retenu et plan écarté

### A. Signature / APNs

Conserver les diagnostics d'échec et ajouter le comptage des callbacks de réception distants. Un jeton obtenu n'est pas présenté comme une preuve de livraison depuis Snapchat. Aucun profil, certificat, jeton ou service payant n'est nécessaire pour compiler le correctif.

### B. Reprise et décodage

Retenus : suivi des récepteurs enregistrés, réception structurée, relais du contenu de notifications internes, correction du premier instantané et du décodage tardif. Le correctif ne modifie pas les serveurs Snapchat et ne tente pas de contourner leur authentification.

Écartée : l'insertion aveugle de `BGTaskSchedulerPermittedIdentifiers` avec un « fallback fetch » parallèle. Apple précise que cette clé désactive les anciennes méthodes `performFetchWithCompletionHandler` et `setMinimumBackgroundFetchInterval` sur iOS 13 et ultérieur. [Apple : tâches d'arrière-plan](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app?changes=_8).

Écarté : appeler arbitrairement `performDeltaSync` parce que son nom apparaît dans des symboles. Le service visé, ses préconditions, son contexte d'exécution et les données synchronisées doivent être établis avant tout appel. Les méthodes originales continuent de s'exécuter normalement ; aucun faux succès de synchronisation n'est enregistré.

### C. Ordre pratique

Utiliser la bibliothèque rc3 compilée, vérifier sa version, puis effectuer un essai corrélé aux diagnostics. Une erreur de signature encore présente reste un problème distinct ; un décodeur qui rejette une réception réellement observée reste un défaut d'adaptation à corriger.

## 7. Résultat de cette vérification

Le document apporte des pistes, mais plusieurs affirmations transforment une inspection statique en certitude d'exécution. La livraison contient un correctif de code compilé et testé sur des fixtures, pas une démonstration du fonctionnement d'APNs pour une IPA Snapchat re-signée. Aucun nouveau test de réception sur iPhone n'a été effectué ici.
