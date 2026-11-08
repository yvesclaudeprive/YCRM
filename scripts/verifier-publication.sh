#!/usr/bin/env bash
# Vérifie qu'aucune donnée personnelle ni aucun secret n'est publié (dépôt public).
# À lancer AVANT chaque push (et lancé par la CI). Code de sortie ≠ 0 = ne pas publier.
# Contrôle : fichiers suivis par git + message du dernier commit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

problems=0
report() { echo "❌ $1"; problems=$((problems + 1)); }

files=$(git ls-files | grep -v -E '^scripts/verifier-publication\.sh$|\.(png|jpg|jpeg|pdf)$')
content() { for f in $files; do [ -f "$f" ] && grep -n -I -H -E -e "$1" "$f"; done; git log -1 --format=%B | grep -n -E -e "$1" | sed 's/^/message du commit:/'; }

# 1. Adresses e-mail réelles (seuls les domaines d'exemple et l'adresse technique des commits sont permis).
emails=$(content '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  | grep -o -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | sort -u \
  | grep -v -i -E '@(example\.(com|org)|exemple\.(com|fr)|anthropic\.com)$|@[0-9]x\.(png|jpg|pdf)$')
[ -n "$emails" ] && report "adresse(s) e-mail : $(echo "$emails" | tr '\n' ' ')"

# 2. Sous-domaine Pipedrive réel (seuls exemple, xxx, test, votre-societe et les variables sont permis).
domains=$(content '[A-Za-z0-9-]+\.pipedrive\.com' | grep -o -i -E '[A-Za-z0-9-]+\.pipedrive\.com' | sed -E 's/^2F//' | sort -u \
  | grep -v -i -E '^(exemple|example|xxx|test|votre-societe|api|developers|www|app)\.pipedrive\.com$')
[ -n "$domains" ] && report "adresse Pipedrive : $(echo "$domains" | tr '\n' ' ')"

# 3. Numéros de téléphone réels (seuls les numéros fictifs des tests et de la doc sont permis).
fictifs='00 00 00 0[0-9]|06 11 22 33 44|0?6 12 34 56 78|01 23 45 67 89|06 00 00 00 01|\+33 7 00 00 00 01|\+33611223344|\+33612345678|\+33700000001'
phones=$(content '(\+33|0033|\b0)[ .]?[1-9]([ .]?[0-9]{2}){4}\b' | grep -v -E "$fictifs" | grep -v -E 'XCTAssert.*e164\("|isLikelyMobile')
[ -n "$phones" ] && report "numéro(s) de téléphone :"$'\n'"$phones"

# 4. Clés, jetons, codes de champs (40 caractères hexadécimaux) hors versions épinglées des actions GitHub.
hex=$(content '\b[0-9a-f]{40}\b' | grep -v -E 'uses: [A-Za-z0-9_./-]+@[0-9a-f]{40}' | grep -v -E 'String\(repeating:')
[ -n "$hex" ] && report "chaîne de 40 caractères hexadécimaux (clé ou code de champ ?) :"$'\n'"$hex"
keys=$(content '-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[abp]-[0-9A-Za-z-]+|ghp_[0-9A-Za-z]{20,}|AKIA[0-9A-Z]{16}|api_token=[^&" ]{8,}')
[ -n "$keys" ] && report "clé ou jeton :"$'\n'"$keys"

if [ "$problems" -eq 0 ]; then
  echo "✅ Rien de personnel ni de secret à publier."
else
  echo "⛔ $problems problème(s) : ne pas publier, prévenir Yves."
  exit 1
fi
