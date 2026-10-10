#!/usr/bin/env bash
# Creates a self-signed code-signing identity in the login keychain so every build
# has the same designated requirement and macOS keeps the Screen Recording grant.
set -euo pipefail

NAME="${1:-Screenshot Local Signing}"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "Identity \"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS="screenshot"
# macOS `security` only understands the legacy PKCS#12 algorithms.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -out "$TMP/identity.p12" -passout "pass:$PASS"

security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created identity \"$NAME\"."
