# Validation iPhone — rc4

Compiler depuis **ce projet complet**. Vérifier la nouvelle exécution GitHub Actions et l'artefact correspondant avant de reconditionner l'IPA. Les anciens artefacts rc3 restent rc3 même si leur nom générique est identique.

Après installation, le journal doit contenir `READY version=4.0.0-rc4 host=14.17.1`.

Ouvrir le chat du compte de test, laisser Snapchat en arrière-plan sans fermer la carte, puis essayer : saisie suivie d'un chat ; deuxième chat ; snap photo ; deuxième snap ; appel. Vérifier les bannières, pas seulement les compteurs.

Le succès de détection doit apparaître dans le callback Arroyo avec `decoded > 0`, puis `eligible > 0`. Le journal doit ensuite afficher `NOTIF-REQUEST type=message` ou `type=snap`, puis `NOTIF-ACCEPTED`. Cette dernière étape signifie acceptation de la demande par iOS, pas preuve de présentation visuelle.

Si `decoded > 0` mais `eligible = 0`, regarder les filtres cumulés `snapshot-missing-time`, `snapshot-direction-unknown`, et le statut `localAccountKnown`. La version rc3 s'arrêtait avant ces filtres ; le fait de corriger son type inconnu ne garantit pas que la date ou l'identité locale soit disponible sur chaque objet.

Si `unknown-content-type` persiste, regarder le nom de la classe, la version hôte, les prédicats booléens et le type numérique dans le nouveau schéma. Ne pas attribuer des numéros au hasard. Les métriques Blizzard sont maintenant ignorées volontairement.

Les fichiers de diagnostic sont toujours `snapnotify.log`, `snapnotify_status.json` et `snapnotify_receive_schema.json`. Ne pas envoyer de corps de message, identifiants de connexion ou données de signature.
