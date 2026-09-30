#!/bin/bash
#
# Configure UNE FOIS la signature des mises à jour de DynamicNotch.
#
#   ./Tools/setup-updates.sh
#
# 1. Crée une paire de clés EdDSA (ou réutilise celle déjà rangée dans le
#    trousseau macOS) ;
# 2. enregistre la clé privée dans le secret GitHub SPARKLE_PRIVATE_KEY
#    (via `gh` si installé, sinon copie dans le presse-papiers + page GitHub).
#
# La clé publique est injectée dans l'app par le workflow de release : il
# n'y a rien à committer. Relancer le script est sans risque : il réutilise
# toujours la clé du trousseau.
#
# ⚠️ Ne régénère jamais une nouvelle clé une fois une version publiée : les
#    copies déjà installées refuseraient toutes les mises à jour suivantes.
#
set -euo pipefail

REPO="dev-thomass/DynamicNotch"
SECRET_NAME="SPARKLE_PRIVATE_KEY"
# Même service que `generate_keys` de Sparkle : la clé reste utilisable avec
# `generate_keys --account dynamicnotch` si besoin.
KEYCHAIN_SERVICE="https://sparkle-project.org"
KEYCHAIN_ACCOUNT="dynamicnotch"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_TOOL="$ROOT/Tools/release/sparkle-key.swift"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "À lancer sur ton Mac." >&2
    exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
    echo "swift introuvable : installe Xcode ou lance « xcode-select --install »." >&2
    exit 1
fi

if PRIVATE_KEY="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)"; then
    echo "✓ Clé de signature trouvée dans le trousseau : elle est réutilisée."
    NEW_KEY=0
else
    echo "→ Génération d'une nouvelle paire de clés…"
    PRIVATE_KEY="$(swift "$KEY_TOOL" generate | sed -n 1p)"
    security add-generic-password \
        -s "$KEYCHAIN_SERVICE" \
        -a "$KEYCHAIN_ACCOUNT" \
        -l "DynamicNotch — clé privée des mises à jour (Sparkle)" \
        -w "$PRIVATE_KEY"
    echo "✓ Clé privée rangée dans ton trousseau (« DynamicNotch — clé privée des mises à jour »)."
    NEW_KEY=1
fi

PUBLIC_KEY="$(printf '%s' "$PRIVATE_KEY" | swift "$KEY_TOOL" public)"
echo "  Clé publique : $PUBLIC_KEY"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    EXISTING_SECRETS="$(gh secret list --repo "$REPO")"
    if [[ "$NEW_KEY" == 1 ]] && grep -q "^${SECRET_NAME}[[:space:]]" <<<"$EXISTING_SECRETS"; then
        echo
        echo "⚠️  Le secret $SECRET_NAME existe déjà sur GitHub, mais aucune clé n'était"
        echo "   dans ce trousseau (autre Mac ?). Le remplacer empêchera les copies déjà"
        echo "   installées de se mettre à jour. Récupère plutôt l'ancienne clé et importe-la :"
        echo "   security add-generic-password -s '$KEYCHAIN_SERVICE' -a '$KEYCHAIN_ACCOUNT' -w 'ANCIENNE_CLE'"
        read -r -p "   Remplacer quand même ? Tape « oui » pour confirmer : " answer
        if [[ "$answer" != "oui" ]]; then
            security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null
            echo "Annulé (la clé fraîchement générée a été retirée du trousseau)."
            exit 1
        fi
    fi
    printf '%s' "$PRIVATE_KEY" | gh secret set "$SECRET_NAME" --repo "$REPO"
    echo "✓ Secret GitHub $SECRET_NAME enregistré."
else
    printf '%s' "$PRIVATE_KEY" | pbcopy
    echo
    echo "La clé privée est dans ton presse-papiers. Sur la page qui s'ouvre :"
    echo "  Name   : $SECRET_NAME"
    echo "  Secret : ⌘V, puis « Add secret »"
    open "https://github.com/$REPO/settings/secrets/actions/new"
fi

echo
echo "C'est prêt. Garde aussi une copie de la clé privée dans ton gestionnaire de"
echo "mots de passe (GitHub ne permet pas de relire un secret). Pour l'afficher :"
echo "  security find-generic-password -s '$KEYCHAIN_SERVICE' -a '$KEYCHAIN_ACCOUNT' -w"
echo
echo "Publier une version : GitHub → Actions → Release → Run workflow (voir docs/DISTRIBUTION.md)."
