# Sources techniques consultées

Les faits concernant cette installation viennent du ZIP et des trois logs fournis, pas d'une documentation supposée du protocole privé Snapchat. Les numéros de champs de l'enveloppe `volatile` et les valeurs `CALLER_PUSH`, `START`, `STOP` sont des observations des trames fournies. Ils ne constituent pas une API Snapchat publique ni une garantie de compatibilité avec les prochaines versions.

Documentation primaire consultée le 8 octobre 2026 :

- Apple — **APS Environment Entitlement** : `https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment`
- Apple DTS — **iOS Background Execution Limits** : `https://developer.apple.com/forums/thread/685525`
- Apple — **Extending your app's background execution time** : `https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time`
- Apple — **Configuring background execution modes** : `https://developer.apple.com/documentation/xcode/configuring-background-execution-modes`
- Apple — **imp_implementationWithBlock** : `https://developer.apple.com/documentation/objectivec/imp_implementationwithblock(_:)`
- Apple — **method_getTypeEncoding** : `https://developer.apple.com/documentation/objectivec/method_gettypeencoding(_:)`
- Apple — **UNUserNotificationCenter.add** : `https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)`
- Protocol Buffers — **Encoding** : `https://protobuf.dev/programming-guides/encoding/`
- Theos — **Variables**, notamment `XXX_OBJCFLAGS` : `https://theos.dev/docs/variables`
- GitHub — **GitHub-hosted runners reference** : `https://docs.github.com/en/actions/reference/runners/github-hosted-runners`

La lecture du format binaire Protobuf permet d'isoler correctement des champs ; elle ne donne pas automatiquement la sémantique d'un champ inconnu. C'est pourquoi les paquets non reconnus sont ignorés et diagnostiqués plutôt que convertis en notifications.
