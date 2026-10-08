# Audit ciblé rc4 : données de l'appareil → correction

## Référence

Projet rc3 fourni dans la conversation, code critique vérifié contre `tomyrms/scnotify` au commit `092adc746dcd1b677bca7cb921c4736d7f318e25`. Les diagnostics concernent Snapchat **14.17.1**, build **14.17.1.0**. Ils ne sont pas inclus dans la distribution pour éviter de republier les identifiants de contacts.

## Ce qui est observé, sans extrapolation

`snapnotify_receive_schema.json` rapporte 15 callbacks Arroyo, 15 rejets `unknown-content-type` et zéro événement décodé. L'objet est `SCNMessagingMessage`, avec un descripteur, un expéditeur, une conversation, des métadonnées et un type numérique dans `SCNMessagingMessageContent`. La dernière forme exportée contient `contentType = 1`. Le schéma ne conserve pas toutes les valeurs de tous les essais, ni les résultats des prédicats natifs ; il ne permet pas d'affirmer que 15 chats distincts ont été perdus, ni de déduire à lui seul le numéro du type snap.

Le journal `snapnotify(4).log` montre ce rejet à 22:33:44.947, 23:13:58.342 et 23:16:41.371, en **BG**. Au moins dans ces fenêtres, les données parviennent au callback sans être converties en événement de notification. La limitation JSON du chemin réseau de secours n'est donc pas l'unique explication : un objet natif était déjà disponible.

Six autres callbacks proviennent de `SCNativeBlizzardLoggerDelegateImpl`, avec un `SCNMessagingReceiveMessageMetricsResult`. Ils fournissent de la télémétrie et ne doivent pas être comptés comme six messages supplémentaires.

Le présentateur synchrone a le retour `B` (`B32@0:8@16@24`) et `installed=false`. rc3 refusait ce retour. C'est un défaut supplémentaire confirmé, mais rien ne prouve que ce présentateur ait été appelé au moment des essais manquants.

Le statut montre zéro perte de paquets/de file, six noms trouvés et aucun échec de résolution de nom sur cette session. L'enregistrement APNs est absent, mais cela n'explique pas le rejet d'objets déjà livrés au récepteur pendant l'exécution du processus.

## Corrections du code

### Classification du modèle réel

`nativeKind()` dans `Sources/SNReceive.m` ne s'applique qu'à `SCNMessagingMessage`. Les prédicats de statut, suppression ou réaction ont priorité pour exclure les événements de contrôle. Un prédicat sémantique de texte/média/note vocale ou de snap fournit ensuite le type. Des prédicats contradictoires sont rejetés.

Lorsqu'aucun prédicat ne conclut, `sn_receive_native_content_kind()` autorise uniquement les valeurs `0` (snap) et `1` (chat), sur `SCNMessagingMessageContent` et pour l'hôte **14.17.1**. Les booléens, nombres flottants, autres classes/versions/valeurs ne profitent pas de ce repli. Les types symboliques existants et les mappings explicites restent disponibles. Le repli ne s'applique pas à un dictionnaire arbitraire ni à un objet analytique. Sa validation iPhone reste nécessaire : une source rétro-conçue n'est pas une spécification Apple/Snapchat du binaire installé.

### Paramètres du callback

`SNDecodeReceiveCallback()` exploite la signature exacte observée. L'UUID de conversation du premier argument sert de contexte ; seul `updatedMessages` est décodé. Le deuxième argument est le contexte de conversation, le quatrième correspond aux suppressions. Un rechargement de toute la conversation ou une suppression ne doit pas produire une réception artificielle.

### Filtres de sens et de fraîcheur

`SNLocalAccountIdentifier()` ne prend que des identifiants explicitement locaux (`currentUserId`, `loggedInUserId`, `selfUserId`), jamais `senderId` ou un `userId` arbitraire. La capture du compte est améliorée sur les objets déjà observés.

Si le compte est inconnu, un indicateur entrant explicite reste utilisable. À défaut, un participant déjà désigné **distant** par Snapchat dans cette même conversation peut établir le sens entrant. Il ne s'agit ni de deviner un message à la fin de la saisie, ni de supposer que tout événement en arrière-plan est entrant. Les données de présence sont vidées lors d'un changement de compte connu, comme auparavant.

La date de création reste nécessaire aux snapshots. Les alias de métadonnées sont élargis, mais une date absente n'est pas remplacée par l'heure courante. Un événement récent dont la direction n'est pas encore connue peut être réévalué lors d'un callback ultérieur ; ce mécanisme ne fabrique pas un nouveau callback et ne promet donc pas un rattrapage sans nouvelle observation.

### Hooks à retour booléen

`SNInstallHook` garde des wrappers distincts `_Bool` et `signed char`, de zéro à deux arguments objets. Le résultat original est conservé, y compris `false` et `-1` pour un char. Les méthodes avec d'autres signatures scalaires restent refusées. Le test Foundation qui attendait auparavant le refus de BOOL est mis à jour ; les nouveaux tests vérifient aussi les valeurs retournées et les appels à l'original.

### Diagnostics

Les schémas contiennent les classes, champs, noms de getters et prédicats booléens, pas les corps de messages. Les candidats décodés sans date ou sans sens connu gardent aussi une forme de métadonnées diagnostiquable. `localAccountKnown` est ajouté au statut. `rejectedTotal` dans le journal est cumulatif par source ; `decoded` et `eligible` sur la même ligne restent propres au lot courant.

## Ce qui n'est pas revendiqué

Aucun décodage d'un nouveau paquet binaire brut n'est inventé. Aucune réception de snap/chat sur iPhone n'a été observée pendant la préparation. Les nouveaux tests Objective-C sont synthétiques : seules leurs formes de classes viennent du diagnostic, pas des messages capturés. La CI et la compilation iOS **rc4 n'ont pas été exécutées**. Les appels, la saisie, l'entrouverture et le maintien audio ont été comparés à rc3 : les fonctions de traitement correspondantes sont inchangées.
