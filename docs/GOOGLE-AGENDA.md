# Bouton « Créer un RDV » : connecter Google Agenda (une seule fois)

Le bouton « Créer un RDV » (ligne des e-mails, juste avant « Décaler la date ») crée le rendez-vous dans votre
Google Agenda, invite le contact (Google envoie l'invitation, avec un lien Google Meet), puis ouvre dans Superhuman le
brouillon « Rendez-vous le jeudi 19 novembre à 10:00 » : il ne reste qu'à appuyer sur Envoyer.

Pour cela, l'app a besoin d'un « ID client » Google (ce n'est pas un secret) et de votre accord, une seule fois.

## 1. Console Google Cloud (10 minutes, sur ordinateur)

1. Ouvrir https://console.cloud.google.com avec votre compte Google de l'agence et choisir (ou créer) un projet.
2. **API et services › Bibliothèque** : chercher « Google Calendar API » › **Activer**.
3. **API et services › Écran de consentement OAuth** (ou « Google Auth Platform ») :
   type d'utilisateur **Interne** (réservé aux comptes de votre organisation, aucune validation Google à demander),
   nom de l'application « YCRM », adresse d'assistance = la vôtre › Enregistrer.
4. **API et services › Identifiants › Créer des identifiants › ID client OAuth** :
   type d'application **iOS**, nom « YCRM iPhone », **ID du bundle `com.yateo.ycrm`** › Créer.
5. Copier l'**ID client** affiché (il finit par `.apps.googleusercontent.com`).

## 2. Dans YCRM (sur l'iPhone)

1. Réglages › **Google Agenda** : coller l'ID client.
2. **Se connecter à Google Agenda** › choisir votre compte › **Autoriser**.
3. « ✓ Google Agenda connecté » : c'est prêt.

L'app ne demande que le droit de **créer des événements** dans votre agenda (portée `calendar.events`).
L'accès reste dans le trousseau de cet iPhone. « Déconnecter Google Agenda » le révoque.
