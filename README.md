# YCRM

App iPhone personnelle (Yateo, dépôt `YCRM`) : **mes activités Pipedrive triées par priorité**, avec les actions du quotidien en un clic.

## Ce que fait l'app

1. Connexion : adresse Pipedrive (le sous-domaine de `xxx.pipedrive.com`) + jeton API personnel, vérifié puis gardé dans le **trousseau de l'iPhone**.
2. Liste de **mes activités** jusqu'à aujourd'hui (filtre de dates modifiable), **triées par « Score priorisation »** de l'affaire, recherche, rechargement en tirant vers le bas, pages de 30.
3. Par activité : société, personne, texte, score, date ; clic = fiche dans l'app Pipedrive.
4. Boutons : OnOff, Aircall, Tél., WhatsApp, « Répondeur ON/OFF », « Répondeur sans message », nouveau mail, réponse au dernier e-mail (Superhuman), mail à moi-même.

## Organisation du code

| Dossier | Rôle |
| --- | --- |
| `Packages/PipedriveKit/` | Logique Pipedrive sans interface : appels API, activités, téléphones, liens vers les apps, formats français. Testée en CI (Linux et macOS). |
| `App/` | Interface SwiftUI (iOS 17+) : connexion, liste des activités, filtre, réglages. |
| `project.yml` | Description du projet Xcode (généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen), non versionné). |
| `.github/workflows/ci.yml` | Tests, compilation de l'app pour le simulateur, scan de secrets. |
| `.github/workflows/testflight.yml` | Envoi sur TestFlight (lancement manuel). |

## Compiler sur un Mac (facultatif)

```bash
brew install xcodegen
xcodegen generate
open YCRM.xcodeproj
```

## Sécurité

- Aucun jeton ni clé dans le code ou le dépôt : le jeton est saisi dans l'app et reste dans le trousseau de l'iPhone.
- Le jeton part dans l'en-tête `x-api-token`, jamais dans l'URL.
- Dépôt public : aucune clé, adresse ni donnée client dans le code ; uniquement des données fictives dans les tests.

## Installation sur l'iPhone

TestFlight : voir [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).
