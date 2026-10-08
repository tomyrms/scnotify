# Validation rc5 — 9 octobre 2026

- **94 tests Python réussis** sur le vrai cœur C compilé en DLL Windows x64 avec Zig 0.15.2 (Clang). Aucun remplacement Python du code de production.
- **200 000 entrées aléatoires** sur les deux parseurs C et les troncatures de la fixture d’appel : succès avec UBSan en mode trap. ASan n’a pas été exécuté ici.
- Les **7 nouvelles régressions sélectionnées échouent sur le cœur C original rc4** : elles reproduisent les défauts corrigés.
- Syntaxe des trois scripts shell vérifiée avec `bash -n`.
- Relecture indépendante des adaptations Objective-C, de la file et du routage des notifications.

Les six programmes Foundation sont inclus dans la CI : TestFoundation, TestReceive, TestHostNotice, TestNativeReceive, TestForeground et TestEventBuffer. Ils couvrent notamment vocaux, dates/directions retardées, rafale de 300 messages décodés, 3000 éléments distincts dans le buffer, rotation du cache et changement du délégué. **Ils n’ont pas été exécutés dans cette session Windows.**

**Non exécutés :** compilation iOS arm64, tests iPhone, comparaison visuelle des bannières, tenue 30 minutes en arrière-plan. Une réussite C ne valide pas les hooks privés de Snapchat ni iOS 26.6.2.

Logs/commandes : `portable-tests-rc5.txt`, `fuzz-tests-rc5.txt`. Pour macOS/Linux, le workflow conserve AddressSanitizer + UndefinedBehaviorSanitizer. Les résultats d’anciennes versions ne sont pas attribués à rc5.
