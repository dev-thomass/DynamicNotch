#!/bin/bash
# Construit l'app dans build/Build/Products/<Configuration>.
# Argument optionnel : Debug ou Release (défaut).
# Signature : si DEVELOPMENT_TEAM est défini, ou si un certificat « Apple Development »
# est dans le trousseau, build signé avec cette équipe (l'autorisation Accessibilité
# tient alors d'un build à l'autre). Sinon, build non signé.
set -o pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
if [ -z "$DEVELOPMENT_TEAM" ]; then
  DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)
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
