# Validation avec tes deux comptes

## Avant le test

Utiliser un seul exemplaire de SnapNotify dans l'IPA. La première ligne `READY` doit indiquer `4.0.0-rc1`. Vérifier que les notifications sont autorisées dans iOS et que les essais ne sont pas masqués par un mode de concentration. Garder un exemplaire de l'ancien IPA pour revenir en arrière.

Compte A = installation testée ; compte B = expéditeur sur l'autre appareil. Ouvrir la liste d'amis puis le profil de B sur A, afin que Snapchat charge les données de nom. Le journal doit montrer une entrée `IDENTITY-LEARNED` si la capture du nom fonctionne. L'absence de cette entrée est un résultat de test, pas une raison d'inventer un alias automatiquement.

Pour voir les décisions au premier plan, mettre provisoirement `NotifyInForeground=true` dans `SnapNotifyConfig.plist`, puis ramener A au premier plan pour recharger le fichier. Revenir à `false` après le diagnostic.

## Série 1 : application A ouverte

| Action sur B | Résultat attendu |
|---|---|
| Commencer à écrire | Une décision `typing`, associée à B et à la bonne conversation. |
| Continuer sans pause | Pas de répétition périodique. |
| Arrêter puis réécrire après cinq secondes | Une nouvelle session, pas un verrou définitif. |
| Recommencer deux minutes plus tard | Nouvelle notification, si une nouvelle présence est bien reçue. |
| Envoyer deux snaps distincts rapidement | Deux événements avec deux IDs, si le callback de réception est pris en charge. |
| Envoyer un message texte | Un événement message, pas snap ni appel. |
| Appeler, laisser sonner puis arrêter | Une notification d'appel ; pas de notification message et pas de nouvel appel lors du STOP. |
| Appeler une deuxième fois | Nouvel appel si son identifiant est distinct. |
| Entrouvrir la conversation | Une décision `peek` seulement si la liste distante de peeking expose l'utilisateur. |

Le signal d'entrouverture dépend des données réellement exposées par Snapchat ; son absence ne doit pas être remplacée par un événement de présence générique.

Pour un troisième compte ou une conversation de groupe, refaire la saisie avec deux personnes. Le nom et le blocage anti-doublons de l'une ne doivent pas affecter l'autre.

## Série 2 : arrière-plan, sans expérience de maintien

Avec `ExperimentalKeepAlive=false`, passer A en arrière-plan puis répéter saisie/snap/appel après 5, 20 et 120 secondes. Refaire avec écran verrouillé. Noter l'heure de chaque action et comparer avec `WIRE`, `PRESENCE`, `NOTIF-REQUEST`, `NOTIF-ACCEPTED` et `DUPLEX-TASK`.

Si les événements cessent d'arriver, le problème est en amont du générateur de notifications. Un `HEALTH` toujours présent ne prouve pas que le socket est connecté ; inversement, l'absence de heartbeat ne permet pas seule de distinguer suspension, terminaison et absence de collecte du fichier.

## Série 3 : essai de maintien optionnel

Activer `ExperimentalKeepAlive=true`, ramener A au premier plan, puis reproduire la série 2. Vérifier `KEEPALIVE-EXPERIMENT` et éventuellement `DUPLEX-BACKGROUND-DEFERRED`. Si le journal dit que le callback est transmis au programme hôte, l'expérience ne diffère pas ce chemin.

Tester aussi un appel vocal, un appel vidéo, l'enregistrement d'un message vocal et la lecture d'un média. Désactiver l'expérience immédiatement en cas de son coupé, micro indisponible, consommation excessive ou dégradation des appels. Ne pas interpréter un essai réussi de deux minutes comme une garantie de fonctionnement permanent.

## Série 4 : robustesse

Fermer complètement puis relancer A ; vérifier que les notifications reprennent après ouverture, sans attendre qu'un processus terminé continue à fonctionner. Alterner premier plan/arrière-plan. Changer de compte connecté dans l'application et vérifier que les états, noms et notifications en attente de l'ancien compte ne sont pas réutilisés.

Refuser temporairement la permission de notification puis la rétablir pour vérifier qu'un échec n'installe pas un verrou permanent. Le rejet doit être visible dans les logs, sans boucle infinie de requêtes.

## Lire le résultat

| Observation | Zone à examiner |
|---|---|
| Aucun nouveau paquet après l'action | Transport, cycle de vie de l'app, APNs ; pas d'abord l'anti-doublons. |
| `WIRE-UNSUPPORTED topic=...` | Le type de paquet n'est pas encore décodé. |
| `RECEIVE-UNSUPPORTED` | Le callback existe mais l'adaptateur ne reconnaît pas suffisamment ses champs. |
| `PRESENCE-UNSUPPORTED` | Le format de présence ne peut pas être lu ; l'ancien état n'est pas transformé en faux arrêt. |
| Nom `unresolved`, `knownUsers=0` | Le modèle/résolveur de nom n'a pas fourni de fiche utilisable. |
| `EVENT-DROP reason=duplicate` | Même événement déjà réservé/traité ; vérifier son type et la chronologie. |
| `NOTIF-FAILED` | Échec de programmation locale, avec domaine/code. |
| `NOTIF-ACCEPTED` sans bannière | Vérifier la présentation et les réglages iOS ; acceptation ne signifie pas affichage. |

Conserver ensemble les deux fichiers de journal tournants et `snapnotify_status.json`. Les nouvelles données n'incluent pas le corps des messages ni les tokens. Le réglage de diagnostic des identifiants complets est à désactiver avant partage public.
