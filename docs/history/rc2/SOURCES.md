# Sources et provenance — rc2

La base vient de `tomyrms/scnotify`, commit `dd9471b02154b2def0f52981f26dced6e829c44e` :
`https://github.com/tomyrms/scnotify/tree/dd9471b02154b2def0f52981f26dced6e829c44e`

`Tweak.m`, lignes 398–449 de la base : liste de callbacks, traitement indépendant des arguments.
`Sources/SNRuntime.m`, lignes 185–228 : extraction plate, IDs signés, dates sans normalisation.
`Sources/SNRuntime.m`, fin du fichier : correctif ARC if/else conservé.

Le texte joint par l'utilisateur décrit la compilation réussie de rc1 et le choix KeepAlive activé. Il ne documente pas le format de messages reçus sur rc2.

Les anciens logs v3 prouvent l'existence, dans cette installation à ce moment-là, de sélecteurs tels que `SCChatConversationUpdaterListenerAnnouncer didConversationViewModelChange:metricsTracker:` et `SCDefaultInAppNotificationPresentingPlugin presentInAppNotificationAsync:delegate:`. Leur installation dans un log ne prouve pas leur déclenchement lors d'un chat entrant sur rc1/rc2.

API primaire vérifiée pour la résolution d'enums : Protocol Buffers, `objectivec/GPBDescriptor.h`, blob `a400fbbc5eb697c6b1cb77923877170027c6ceca`.
`https://github.com/protocolbuffers/protobuf/blob/main/objectivec/GPBDescriptor.h`
Le descripteur expose `fields`, le champ `enumDescriptor`, puis `textFormatNameForValue:(int32_t)` et `enumNameForValue:(int32_t)`. Cette API justifie la technique de résolution conditionnelle ; elle ne prouve pas que tous les objets Snapchat sont des GPBMessage.

Des recherches externes de compatibilité ont donné la piste des objets descriptor/messageContent. Les tests qui couvrent ces structures sont explicitement synthétiques, et aucune valeur numérique d'enum ni aucun protocole de chat privé n'a été importé d'une autre plateforme comme s'il avait été vérifié sur iOS.

Les références générales de la livraison précédente (Apple/Theos/format Protobuf) sont conservées dans `history/rc1/SOURCES.md` ; elles n'ont pas toutes été revérifiées pour cette livraison. Les observations et les limites de rc2 sont décrites dans `CORRECTION_CHATS_SNAPS.md`.
