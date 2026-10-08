# Audit du projet et des logs

## Périmètre

Les six fichiers du ZIP fourni ont été lus : `Tweak.m` (840 lignes), `Makefile`, `control`, `README.md`, `.gitignore` et `.github/workflows/build.yml`. Les journaux analysés sont `snapnotify(1).log` (10 403 lignes), `(2)` (7 227) et `(3)` (7 025).

Base : commit indiqué dans l'archive `87bc01f597134c3f9aa82f675f33a2823948ba7d`. Les numéros de lignes « v3 » ci-dessous concernent le `Tweak.m` original, pas le nouveau fichier.

## 1. Les appels étaient réellement reçus, mais mal classés

**Preuve :** le journal `(3)`, lignes 6 998–7 023, contient des enveloppes `volatile` et du JSON avec `messageType=CALLER_PUSH`, `callAction=START/STOP`, `callUuid`, `skipRinging` et un expéditeur. La v3 cherche des mots dans les octets (`sck_duplex_kind`, lignes 72–80) ; le mot `message` contenu dans `messageType` suffit donc à classer un appel comme message. Les informations de transport `STREAMER_DATA_VC2` sont également classées « message ».

À 18:17:48.873, l'appel est annoncé comme un message. À 18:17:53.890, sa retransmission est annoncée à nouveau. À 18:17:57.680, la fin de l'appel produit encore un « nouveau message ».

**Correction :** lecteur Protobuf borné, validation de l'enveloppe puis lecteur JSON validant les champs exacts. Seul `CALLER_PUSH / START` avec politique de sonnerie explicite crée l'événement. `STOP` annule une attente et pose une marque anti-retransmission. Déduplication par `callUuid`, pas par deux secondes de silence. `STREAMER_DATA_VC2` est ignoré.

**Vérification exécutée :** 14 trames anonymisées du log rejouées avec le cœur C de production : 10 trames d'appel et 4 trames de transport ; la séquence produit une seule décision de notification d'appel en arrière-plan, sans les trois messages de la v3. Ceci ne teste pas la présentation iOS de la bannière.

## 2. Résolveurs de noms exclus et associations ambiguës

**Preuve code :** `snapchatterForUserId:` figure dans les cibles, mais ne bénéficie pas du chemin spécial des quelques résolveurs reconnus par sous-chaîne (v3, lignes 625–641). Le filtre général n'accepte que les retours `void` ; une méthode retournant un objet n'est donc pas branchée. Les tentatives d'intercepter des initialiseurs SOJU sont aussi rejetées par ce filtre. Le seul résolveur à retour objet mentionné dans le log `(3)` est `_displayNameForUserId:` sur une classe de prévisualisation de Lens ; aucun `NAMECACHE` n'est enregistré.

L'extraction générique accepte aussi `recipientUsername`, `conversationName`, `title` et des clés contenant vaguement « name ». Elle recherche l'identifiant de conversation avant celui d'utilisateur. Cette combinaison peut associer la mauvaise personne, particulièrement dans un groupe. La regex des noms ne prend pas correctement en charge les espaces et tous les caractères Unicode.

**Correction :** observation après le retour des résolveurs explicitement nommés ; capture des getters/setters des modèles de personnes et des données utilisateur déjà reçues par l'application. Lecture avec signature vérifiée, normalisation des UUID `NSString`/`NSUUID`, nom affiché prioritaire, pseudonyme de secours. Cache séparé des conversations, limité à 2 048 personnes et protégé sur disque. Le cache v3 ambigu est abandonné. Les changements de compte réinitialisent les états et annulent les notifications locales propres à l'ancien compte ; l'apprentissage initial du compte ne supprime pas le premier appel.

**Limite :** un UUID ne contient pas le nom de la personne. Les résolveurs doivent effectivement fournir leur résultat sur cette version de Snapchat. Le correctif crée le chemin de récupération qui manquait ; il ne peut pas garantir qu'un nom absent des données sera disponible. Alias manuel documenté, sans nom inventé.

## 3. Saisie : une regex et un délai ne modélisent pas une session

**Preuve code :** le traitement de présence prend le premier `remoteTypingParticipants`, le premier utilisateur et la première conversation trouvés dans la description d'un tableau (v3, lignes 458–490). Plusieurs conversations ou participants ne sont pas traités correctement. Le délai est de **15 secondes**, enregistré seulement quand une notification est créée.

**Rectification du diagnostic précédent :** ce délai de 15 secondes, à lui seul, ne justifie pas qu'une nouvelle activité arrivée deux minutes plus tard soit bloquée. Il faut aussi vérifier que l'événement arrive encore et que l'application est exécutée. Les logs ne prouvent pas un verrou anti-doublons permanent.

**Correction :** traitement de chaque conversation et participant ; état de session par type/conversation/utilisateur ; réarmement après arrêt ou expiration d'inactivité ; protection contre le rebond et les horodatages rétrogrades. Une notification attendant le nom est annulée si la personne a déjà cessé d'écrire. Les utilisateurs ne partagent pas une clé `typing|?`.

**Prudence sur le protocole :** les valeurs numériques `typingState=1/3` ne sont pas interprétées comme une énumération officielle. Un booléen `isTyping` est utilisé quand il existe ; sinon, l'appartenance à `remoteTypingParticipants` sert de signal et l'état brut reste diagnostiqué. `TypingInactiveStates` permet un ajustement après un test contrôlé. Une description typée est un repli par conversation uniquement, pas un protocole public stable.

## 4. Les snaps ne sont pas démontrés dans les captures

Aucun paquet complet identifié comme réception de snap n'est présent dans les logs fournis. Le dernier log contient 24 entrées Duplex classées `presence` et 14 entrées auparavant classées `message`, qui sont en réalité les trames d'appel/transport précédentes. Une absence de hook ne prouve pas que Snapchat n'a pas reçu le snap par un autre chemin.

**Correction côté code :** adaptateurs sur callbacks explicites de réception, signatures vérifiées, type sémantique reconnu et identifiant de message obligatoire. Rejet des messages sortants, historiques et accusés de lecture reconnus. Les enums numériques inconnues ne sont pas devinées. Deux messages distincts n'utilisent plus une clé globale par type/expéditeur.

**Non validé :** l'existence et le déclenchement de ces callbacks dans le Snapchat installé. `HOOK` indique les méthodes réellement trouvées et `RECEIVE-UNSUPPORTED` les payloads non interprétés. Aucun événement générique « activité » ne remplace cette incertitude. Cela exige un essai de réception sur l'appareil avant de déclarer la fonction corrigée de bout en bout.

## 5. Arrière-plan : activité du processus ≠ connexion Snapchat permanente

La v3 force `AVAudioSessionCategoryPlayback`, y compris au premier plan et deux secondes après une interruption (lignes 276–295 et 785–815). Maintenir un lecteur audio ne prouve pas que le composant Duplex laisse sa connexion ouverte. Les logs montrent aussi `endBackgroundTask`. **Ce callback ne prouve ni une suspension effective par iOS, ni à lui seul la fermeture du socket.**

**Correction :** maintien audio rendu optionnel, désactivé par défaut, contrôles du mode `audio` et de la session d'enregistrement/appel. Expérience explicite de report du callback de mise en arrière-plan Duplex observé, uniquement sur le thread principal ; pas d'appel à un sélecteur de reconnexion inventé, pas de falsification de `UIApplication.applicationState`, pas de détournement de `begin/endBackgroundTask`.

Les interruptions arrêtent l'expérience sans désactiver la session audio partagée de Snapchat. Un indicateur de dernière réception aide à distinguer les problèmes de transport des problèmes de notification. Cette expérience reste non validée sur appareil et ne contourne pas les limites d'exécution iOS.

## 6. APNs : problème distinct, non réparable par une clé ajoutée au code

Le dernier journal contient deux erreurs d'enregistrement APNs 3000 ; les précédents en contiennent également. Les notifications locales ne rétablissent pas la réception distante une fois le processus inactif.

L'archive comprend un inspecteur d'IPA en lecture seule. Les entitlements réellement signés, les permissions du profil et l'association côté serveur sont trois vérifications distinctes. Aucun entitlement n'est injecté artificiellement, et aucun succès APNs n'est simulé.

## 7. Sécurité des hooks et respect du programme hôte

Les wrappers v3 recherchent l'IMP original en remontant depuis la classe dynamique de l'objet. Le code tente déjà de prévenir certains conflits d'héritage, mais ce mécanisme global est fragile. Le chemin des résolveurs ne valide pas complètement la signature. `sck_hook_duplex` n'exclut pas les destructeurs comme le fait l'autre scanner ; `.cxx_destruct` apparaît effectivement dans le dernier journal.

La v4 capture l'IMP original dans un bloc propre à la classe qui déclare la méthode. L'original est appelé avant l'observation ; la réentrance des lecteurs ne réexécute pas les observateurs. Les retours et arguments sont contrôlés, les pointeurs et signatures scalaires non prises en charge sont refusés. Les méthodes `init/new/copy/alloc`, destructeurs et `applicationWillTerminate:` ne sont pas remplacées par des wrappers génériques.

**Nuance sur les logs :** `(3)` commence par 3 031 répétitions de `applicationWillTerminate:` à 18:16:33, avant le nouveau scan de 18:16:43. C'est un indice d'un problème dans une exécution antérieure, pas une preuve que la version du ZIP reproduit exactement cette récursion. Un test Foundation dédié à l'héritage est fourni mais n'a pas été exécuté dans l'environnement Linux.

## 8. Notifications natives et échecs de programmation

La v3 recopie certaines notifications déjà programmées par Snapchat, ce qui peut produire des doublons. Elle transforme aussi des notifications internes en « activité ». La v4 ne recopie plus globalement les notifications natives ni `NSNotificationCenter`.

Un registre borné réserve une décision, puis la confirme après l'acceptation par `UNUserNotificationCenter`. Un échec libère la réservation et peut déclencher une seule nouvelle tentative ; une ancienne completion ne supprime pas une décision plus récente. Une absence d'autorisation n'entraîne pas de boucle de tentatives. La présentation au premier plan ne traite que les notifications marquées SnapNotify et appelle le completion handler exactement une fois ; les notifications du programme hôte suivent leur chemin original.

## 9. Concurrence, journaux et compilation

L'état métier et la persistance sont sérialisés. UIKit et l'audio restent sur le thread principal. Les objets privés sont lus dans le callback d'origine puis transformés en instantanés ; ils ne sont pas inspectés arbitrairement depuis une autre file. Le nombre de paquets en attente, les buffers, les caches et les registres sont bornés.

Le journal dispose de sa propre file, d'une rotation conservant une génération précédente et d'une marque de session/version. Il ne copie plus les données binaires, contenus de chat, adresses IP, tokens ou noms de contacts. Les UUID sont abrégés par défaut.

La syntaxe de `control` est corrigée (`Package:`). Le workflow utilise le SDK du Xcode installé, compile un chemin de sortie déterministe et échoue si l'artefact manque. La voie Theos reste disponible, avec les flags ARC réservés aux fichiers Objective-C. Aucun build distant ni changement du dépôt GitHub n'a été effectué pendant la création de cette archive.
