# Mettre YCRM sur l'iPhone (TestFlight)

À faire **une seule fois** par Yves, dans les consoles Apple et GitHub. Aucune valeur n'est à envoyer dans le chat.

## 1. Compte Apple Developer actif
Attendre l'e-mail « Bienvenue dans l'Apple Developer Program » (jusqu'à 48 h après le paiement).
Puis noter l'**ID d'équipe** (10 caractères) : developer.apple.com › Account › Membership details › *Team ID*.

## 2. Déclarer l'identifiant de l'app
developer.apple.com › Certificates, Identifiers & Profiles › **Identifiers** › **+** › *App IDs* › *App* :
- Description : `YCRM`
- Bundle ID : **Explicit** › `com.yateo.ycrm`
- Aucune option à cocher › *Continue* › *Register*.

## 3. Créer la fiche de l'app
appstoreconnect.apple.com › **Apps** › **+** › *Nouvelle app* :
- Plateforme : iOS · Nom : `YCRM` (le nom doit être unique chez Apple : s'il est pris, `YCRM Yateo` ; l'iPhone affichera toujours « YCRM »)
- Langue principale : Français · Bundle ID : `com.yateo.ycrm` · SKU : `ycrm` · Accès : complet.

## 4. Créer la clé API pour GitHub
appstoreconnect.apple.com › **Utilisateurs et accès** › **Intégrations** › *API App Store Connect* › *Clés d'équipe* (la 1re fois : *Demander l'accès*) › **+** :
- Nom : `GitHub TestFlight` · Accès : **Admin** (nécessaire pour que GitHub fasse signer l'app par Apple).
- *Générer* puis **Télécharger la clé** (fichier `AuthKey_XXXX.p8`, téléchargeable **une seule fois**).
- Noter l'**ID de la clé** et l'**ID de l'émetteur** (Issuer ID) affichés sur la page.

## 5. Déposer les 4 secrets dans GitHub
github.com/yvesclaudeprive/YCRM › **Settings** › *Secrets and variables* › **Actions** › *New repository secret* :

| Nom | Valeur |
| --- | --- |
| `APPLE_TEAM_ID` | ID d'équipe (étape 1) |
| `ASC_KEY_ID` | ID de la clé (étape 4) |
| `ASC_ISSUER_ID` | ID de l'émetteur (étape 4) |
| `ASC_PRIVATE_KEY` | tout le contenu du fichier `.p8` (ouvert avec le Bloc-notes), lignes `BEGIN` / `END` comprises |

Ensuite, **supprimer le fichier `.p8`** du PC (Téléchargements + corbeille). En cas de perte, on révoque la clé et on en crée une nouvelle.

## 6. Envoi et installation
- Claude lance l'envoi (Actions › `testflight` › *Run workflow*). Apple traite la version en 10 à 30 min.
- App Store Connect › l'app › **TestFlight** › *Test interne* › **+** créer un groupe (ex. « Yves ») › s'y ajouter, cocher la distribution automatique.
- Sur l'iPhone : installer l'app **TestFlight** (App Store), se connecter avec le même identifiant Apple, installer **YCRM**.
- 1er lancement : saisir le sous-domaine Pipedrive (`xxx` de `xxx.pipedrive.com`) et le jeton API Pipedrive (Pipedrive › Préférences personnelles › API).

## Révoquer / retour arrière
- Clé API : App Store Connect › Intégrations › révoquer `GitHub TestFlight` (l'app installée continue de marcher).
- Jeton Pipedrive : dans l'app, Réglages › *Supprimer le jeton de cet iPhone* ; et/ou régénérer le jeton dans Pipedrive.
