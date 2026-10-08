# Validation effectuée — 4.0.0-rc3

## Validation distante réelle

- Dépôt : `tomyrms/scnotify`.
- Branche isolée : `chatgpt/rc3-notification-validation`.
- Commit de validation : `47be842e27496821cd6a3564881b40df60ec8153`.
- Exécution : [37843432418](https://github.com/tomyrms/scnotify/actions/runs/37843432418). Job : `113538280382`.
- Conclusion retournée par GitHub : `success`. Toutes les étapes de préparation, tests, compilation et publication ont réussi.

Le workflow restaure un patch SHA-256 vérifié avant de l'appliquer à la base. Empreinte du patch : `31f9ce692ad64762b3a1a3c73ed0bb2018a184a50c84844a76f74bdfc1ad478f`. La branche est un montage de validation, pas une branche destinée à être fusionnée telle quelle. `main` n'a pas été modifiée.

## Résultats des journaux du job

`78` tests Python/C réussis. Ces tests exécutent le code C compilé ; ils ne constituent pas les nouveaux tests du relais Objective-C.

`100 000` entrées déterministes plus les troncatures de la fixture du cœur sous AddressSanitizer/UndefinedBehaviorSanitizer, puis `100 000` entrées de la politique de réception sous les mêmes sanitizers : aucune erreur signalée dans ces corpus. Il ne s'agit pas d'un fuzzer de Snapchat ni du nouveau relais Objective-C.

Tests natifs macOS, compilés et exécutés par `scripts/test-macos.sh` :

| Programme | Assertions réussies |
| --- | ---: |
| Foundation/runtime | 46 |
| Receive adapters/runtime | 107 |
| Host bridge and receive fixes | 52 |

Ces `205` assertions natives utilisent des fixtures synthétiques, sauf le corpus d'appel anonymisé historique utilisé séparément par les tests du cœur. Elles couvrent notamment l'appel à l'original, les signatures incompatibles, les champs optionnels, la référence initiale et la lecture tardive. Ce ne sont pas 205 messages réels reçus.

La compilation iOS a produit `out/SnapNotify.dylib`, identifiée par le runner comme une bibliothèque Mach-O arm64. [Artefact compilé](https://github.com/tomyrms/scnotify/actions/runs/37843432418/artifacts/11578248481). Empreinte SHA-256 du ZIP d'artefact annoncée par GitHub : `dbadacc8bc30c2e5b5f4e44569dc3d1e06dbfb60149810900dcd38a84d92cee7` ; cette empreinte concerne le ZIP GitHub, pas le ZIP des sources ni la dylib seule.

## Correspondance avec les fichiers livrés

Le job a écrit les empreintes SHA-256 des 26 fichiers de code, tests et scripts existants utilisés. Elles sont reproduites dans `SOURCE_HASHES_CI.json`. Elles ont toutes été comparées avec les fichiers de ce ZIP et correspondent exactement. Les changements de documentation, de version de package et d'exemple de configuration effectués ensuite n'ont pas modifié ces 26 fichiers.

Le workflow normal fourni dans `.github/workflows/build.yml` compile directement les sources étendues de cette archive, sans le mécanisme de transport du patch de la branche isolée.

## Non réalisé

Aucune installation de rc3 sur iPhone, aucun essai réel d'envoi de chat/snap sur rc3, aucune validation de livraison APNs depuis les serveurs Snapchat et aucune mesure d'autonomie. Les IPA WhatsApp/profils cités dans le document DeepSeek n'ont pas été fournis ni analysés à nouveau. Une compilation réussie ne valide pas les adaptateurs privés sur chaque version de Snapchat.
