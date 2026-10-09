# Vérifications rc7

Exécuté ici sur Windows x64, avec Zig 0.15.2 compilant les sources C de production :

- Suite complète : **115 tests réussis**, sortie enregistrée dans `portable-tests-rc7.txt`.
- Nouveau décodeur de présence : 21 tests de protocole, drapeaux texte/vocal, UUIDs, groupes, types incorrects, duplications, dépassements, troncatures et échec transactionnel.
- Fuzzer du nouveau décodeur : **100 000 entrées mutation/aléatoires**, plus troncatures, avec UBSan. Commandes et compte rendu dans `fuzz-presence-rc7.txt`. Pas d’ASan dans cette exécution Windows; la CI POSIX conserve ASan+UBSan.
- Syntaxe des trois scripts shell vérifiée avec `bash -n`.
- Relecture indépendante de l’intégration des états, des changements de média, de l’annulation des notifications en attente et de l’isolation des conversations/comptes.
- ZIP et manifeste SHA-256 vérifiés après génération.

**Non exécutés ici :** les sept programmes Foundation, compilation iOS, réception réseau réelle sur iPhone et affichage des deux bannières. Le nouveau test `TestPresenceActivity` couvre le cache texte/vocal, l’expiration, l’arrêt, les groupes, les données invalides et le reset; il sera exécuté sur le runner Mac.

Le schéma de protocole est corroboré par une implémentation publique indépendante. Les fixtures sont synthétiques et ne constituent pas une capture de vocal sur Snapchat iOS 14.17.1. Les anciens journaux rc5 restent historiques.
