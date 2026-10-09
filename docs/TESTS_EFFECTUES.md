# Vérifications rc9

- Suite complète exécutée : **143 tests C/Python réussis** sur Windows. Journal réel : `portable-tests-rc9.txt`.
- Les 140 tests rc8 ont été conservés. Les trois nouveaux tests vérifient le format PCM/durée, l’identité des octets embarqués avec le WAV et son empreinte de provenance.
- `python scripts/embed_sound.py --check` confirme que la ressource et l’en-tête de compilation concordent.
- Syntaxe des trois scripts shell vérifiée individuellement avec `bash -n`.
- Relecture des deux chemins de notification, du chargement des anciens réglages et de l’installation du fichier audio.
- Archive et manifeste SHA-256 vérifiés après génération.

**Non exécuté ici :** compilation iOS, huit programmes Foundation et écoute d’une notification sur iPhone. Le nouveau `TestNotificationSound` vérifie installation, réutilisation, réparation et erreurs de fichiers; il est branché au script macOS mais requiert Foundation.

La validation Windows ne remplace pas l’exécution de `UNUserNotificationCenter` sur l’appareil. Aucun nouveau fuzzing ni test de batterie n’est revendiqué pour rc9. Le son est le fichier générique extrait de l’IPA fournie, pas un son recréé ou téléchargé sur un site tiers.
