#!/bin/bash
# Construit l'app dans build/Build/Products/<Configuration>.
# Argument optionnel : Debug ou Release (défaut).
# Signature : si DEVELOPMENT_TEAM est défini, ou si une identité « Apple Development »
# valide est dans le trousseau, build signé avec cette équipe (l'autorisation
# Accessibilité tient alors d'un build à l'autre). Sinon, build non signé.
set -o pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
if [ -z "$DEVELOPMENT_TEAM" ]; then
  # Empreinte SHA-1 de la première identité « Apple Development » valide
  # (certificat non expiré, non révoqué, avec sa clé privée).
  IDENTITY_SHA1=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) "Apple Development: .*/\1/p' | head -1)
  if [ -n "$IDENTITY_SHA1" ]; then
    # Équipe = OU de ce certificat précis (un certificat expiré peut porter le même nom).
    DEVELOPMENT_TEAM=$(security find-certificate -a -Z -p -c "Apple Development" 2>/dev/null \
      | awk -v sha1="$IDENTITY_SHA1" '
          /^SHA-256 hash:/ { keep = 0; next }
          /^SHA-1 hash:/ { keep = ($3 == sha1); next }
          keep' \
      | openssl x509 -noout -subject 2>/dev/null \
      | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)
  fi
fi
if [ -n "$DEVELOPMENT_TEAM" ]; then
  echo "Signature : équipe $DEVELOPMENT_TEAM"
  SIGN_ARGS=(CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" -allowProvisioningUpdates)
else
  echo "Signature : aucune (build non signé)"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration "$CONFIG" \
  -derivedDataPath build "${SIGN_ARGS[@]}" \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v "appintentsmetadataprocessor" | tail -60
