# Correction ciblée — rc2

## Périmètre et preuves

Base de code : `tomyrms/scnotify`, commit `dd9471b02154b2def0f52981f26dced6e829c44e`. Le retour utilisateur indique que les appels et la saisie fonctionnent. Le texte `Texte collé(20261008-171841).txt` décrit la correction de compilation et le reconditionnement de rc1 ; ce n'est pas un journal de réception de rc1. Les anciens journaux v3 ne fournissent pas de trame chat/snap suffisamment identifiée pour valider un décodeur binaire.

Les défauts ci-dessous sont constatés dans le code de référence. Leur présence est établie ; leur rôle exact dans chaque essai récent ne l'est pas faute de nouvelles traces.

| Défaut dans rc1 | Changement rc2 | Limite de vérification |
|---|---|---|
| Recherche des IDs uniquement au premier niveau | Lecture du descripteur et des enveloppes imbriquées | Layouts synthétiques ; layout exact de l'iPhone à confirmer |
| Chaque argument de callback décodé isolément | Conservation du paramètre conversation explicitement nommé | Pas de déduction à partir d'un UUID arbitraire |
| `longLongValue > 0` sur les IDs numériques | Conversion décimale sans perte des uint64 | Test Foundation prévu, pas exécuté ici |
| UUID natif avec champ `id` binaire non reconnu | Lecture des 16 octets UUID enveloppés | Pas de lecture brute d'un pointeur inconnu |
| Dates numériques traitées directement en secondes | Normalisation s/ms/us/ns | Politique C testée ; métadonnées hôte à confirmer |
| Seulement sept noms de callbacks de réception | Sélecteurs explicites supplémentaires, callbacks multi-arguments et observateurs de conversation | Chaque hook reste un candidat jusqu'à son exécution sur l'appareil |
| Valeurs numériques ignorées | Résolution via descripteur d'enum hôte et correspondance par classe facultative | Aucune correspondance globale 1=chat/2=snap supposée |
| Mises à jour de conversation non exploitées | Référence initiale, comparaison des identifiants et dates | Référence initiale volontairement silencieuse |
| Logs de réception insuffisants | Schéma, signatures, compteurs, motifs de rejet | Aucun corps de message ni description complète |

## Chemin d'exécution

`callback → SNInstallHook → observeReceived → SNDecodeReceived → consumeReceiveBatch → consumeReceived → notifyEvent → deliver`

L'observation ne remplace pas le fonctionnement du callback : l'implémentation originale s'exécute d'abord. Chaque hook capture son propre IMP. Les arguments sont lus de façon bornée sur le thread du callback, puis les valeurs Foundation détachées sont envoyées à la file sérialisée du tweak. Les objets internes Snapchat ne sont pas conservés dans le cache d'événements.

Les nouveaux adaptateurs n'analysent pas le texte d'un chat pour décider s'il s'agit d'un snap, ne prennent pas la fin d'une saisie comme preuve qu'un chat a été envoyé, et ne traitent pas `sync_trigger` comme un message. Cela évite de réintroduire les fausses notifications de la v3.

Pour un observateur de conversation (par opposition à un callback de réception explicite), la première image est mémorisée sans alerte. Seuls les nouveaux IDs ayant une date récente et postérieure à cette référence peuvent être notifiés. Les IDs encore non décodés sont également mémorisés : leur déchiffrement ultérieur ne crée pas un nouvel événement. Les caches sont bornés (128 conversations, 2048 IDs chacune), avec réinitialisation au changement de compte ; saturation d'un ensemble d'IDs = arrêt conservateur de ce chemin plutôt que fausses répétitions.

## Préservation des fonctions opérationnelles

`Core/SNCore.c` et `Core/SNCore.h` sont inchangés. Les corps des fonctions de décodage des appels, de gestion des sessions de présence et du maintien audio ont été comparés à la base. Le correctif ARC en `if/else` est conservé. Le nouveau filtrage « observé au premier plan » concerne les événements de réception ; les clés appel/saisie/chat/snap restent distinctes.

Aucune assertion ne dit que rc2 a reçu un vrai snap sur l'iPhone. Le défaut d'interprétation est corrigé pour les structures supportées, mais les signatures et layouts réels de la version installée doivent encore être confirmés. Un callback qui n'existe pas ne peut pas devenir fonctionnel grâce à des tests synthétiques.

## Fichiers principaux

- `Sources/SNReceive.m/.h` : adaptateurs, extraction, diagnostic, comparaison des images de conversation.
- `Core/SNReceivePolicy.c/.h` : sélection bornée de candidats, classification symbolique, dates.
- `Sources/SNRuntime.m` : UUID enveloppés et hooks à quatre arguments objets.
- `Tweak.m` : intégration, inventaire des hooks et compteurs, sans modification des parseurs d'appel/pré­sence.
- `tests/TestReceive.m` : fixtures Objective-C synthétiques, exécutées par la CI Mac.
- `tests/test_receive_policy.py` et `tests/fuzz_receive.c` : validation portable du code C de production.

## Interpréter le prochain essai

`receiveCallbacks=0` : aucun callback de cette sélection n'a été observé ; ce n'est pas un blocage de déduplication. Un hook `installed=false` donne sa signature exacte pour écrire un wrapper correctement typé, plutôt qu'une conversion non sûre.

`unknown-content-type` : l'objet est reçu mais le type est inconnu. Vérifier la classe et la valeur d'enum affichées dans le schéma ; ne pas renseigner une table de nombres au hasard. `missing-conversation`, `missing-message-id` ou `missing-sender` indique quel élément manque. Les getters déclarés du type peuvent guider l'adaptation suivante sans exposer le contenu du message.

`decodedMessages`/`decodedSnaps` augmente sans bannière : vérifier le premier plan, la référence initiale des observateurs, l'identité du compte local, la date, les réglages des catégories et les motifs `EVENT-DROP`. Une valeur « decoded » n'est ni une tentative de bannière ni sa confirmation visuelle.
