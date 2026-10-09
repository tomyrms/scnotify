# Vérification rc6 — correction du libellé de préparation

## Vérifications exécutées pour cette livraison

- Comparaison exacte avec l’archive rc5 livrée : dans les sources de production, seul `Tweak.m` change, pour le libellé et le numéro de version. Le champ version du paquet `control` est également actualisé.
- Le libellé de présence est maintenant « prépare un message… » ; le libellé de réception « t’a envoyé un vocal » est conservé.
- Tous les fichiers `Core/`, `Sources/`, `tests/`, les scripts et le workflow sont identiques octet pour octet à rc5.
- Intégrité ZIP, liste de fichiers et manifeste SHA-256 vérifiés après empaquetage.

Il s’agit d’une correction de texte : aucun test supplémentaire reproduisant la chaîne de caractères n’est ajouté. Les 94 tests C/Python et les 200 000 essais aléatoires consignés dans les journaux **rc5** n’ont pas été relancés pour cette modification. Ces résultats restent ceux de rc5, dont le cœur C est inchangé.

Compilation Objective-C/iOS et essais iPhone rc6 **non exécutés ici**, faute de SDK Apple sur Windows. L’utilisateur a confirmé le bon fonctionnement général de rc5 ; ce retour ne constitue pas une validation de rc6 ni une mesure exhaustive des notifications.

Le workflow existant recompilera et exécutera les six programmes Foundation avant de produire la nouvelle dylib.
