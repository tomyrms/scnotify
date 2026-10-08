# Audit ciblé rc5

## Défauts constatés dans la base rc4

1. `nativeKind` reconnaissait déjà `isVoiceNote`, mais `bodyFor` annonçait tous les contenus de chat comme « message ». Les nouveaux sous-types sont conservés jusqu'à l'affichage et les getters déjà observés sur l'iPhone servent de source.
2. `observeReceived` et `observeHostNotice` abandonnaient le callback dès 64 traitements en vol. Ce garde-fou est remplacé par une contre-pression pour les données structurées. Le chemin de paquets réseau conserve sa borne distincte et ses compteurs : il n'est pas présenté comme illimité.
3. `collect` limitait un lot à 256 éléments. Les grandes collections des callbacks identifiés sont maintenant découpées avant cet appel ; chaque élément reste soumis aux mêmes contrôles.
4. `SNReceiveTracker` ne traitait plus les nouveaux identifiants après saturation de son ensemble de 2048 entrées. Il utilise une fenêtre tournante, avec une déduplication supplémentaire dans la file de contenu.
5. Les attentes de notification étaient supprimées après 15 s par `writeStatus`. Cette limite reste pertinente pour des états périssables comme la saisie, pas pour une rafale de chats/snaps : ces derniers utilisent maintenant une file séparée.
6. Le sens distant était déterminé par la présence des clés transitoires `typing|conversation|uid` / `peek|conversation|uid`. L'effacement de ces clés après une période d'inactivité ne signifie pourtant pas que la personne est devenue le compte local. La preuve d'identité distante est séparée de l'état d'activité.
7. Une interruption audio commencée sans événement de fin pouvait laisser `audioInterrupted` bloqué malgré une reprise utilisateur. Le retour réel au premier plan le réarme. Le contrôle périodique est enregistré dans les modes communs de la boucle principale.
8. Tout appel à `sessionWrapper:updatedState:` coupait l'expérience audio, même sans preuve que le micro/appel la nécessitait. Le contrôle de catégorie audio est ajouté ; le décodage CALLER_PUSH est inchangé.

## Ce qui n'est pas démontré

Le retour utilisateur confirme rc4 pour chats/snaps et décrit une coupure après dix minutes et des pertes en rafale. Il n'y a pas de nouveau journal rc4 correspondant à ces deux symptômes. Les défauts ci-dessus sont constatés dans le code ; les tests reproduisent notamment la saturation et la perte de preuve distante, mais ne prouvent pas que chacun se produit lors du dernier essai réel. Les chemins AVAudioSession sont compilés, pas exercés sur l’appareil. Aucun test ne prouve un maintien réseau pendant 30 minutes sur iPhone. Pas de promesse d'une bannière séparée pour chaque demande acceptée par iOS.

## Preuves existantes et portée

Le schéma fourni auparavant (rc3) expose `SCNMessagingMessage.isVoiceNote`, les getters de médias, stickers et réponses aux stories. Les tests de l'adaptateur emploient ces signatures sur des modèles synthétiques. Les journaux rc3 ne sont pas réinterprétés comme des captures rc5. Le projet est construit à partir de rc4 `6692b9f`.

## Sources Apple vérifiées

- Exécution en arrière-plan : https://developer.apple.com/forums/thread/685525
- Interruptions audio, notamment l'absence possible d'événement de fin : https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html
- Demande locale et déclenchement immédiat : https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)
- Affichage et regroupement : https://support.apple.com/en-us/108781

Les sources de plateforme ne documentent pas les interfaces privées de Snapchat. Les compatibilités privées restent bornées aux modèles réellement observés et sont à revalider après une mise à jour de l'hôte.
