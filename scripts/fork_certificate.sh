#!/bin/bash
# Run once on your Mac. Makes the free certificate RecallDiscord is signed with and saves it as secrets on the fork.
# It holds only the name below. Keep the copy it leaves in your home folder: a new certificate means everyone
# reinstalls by hand, because the updater only accepts the certificate that signed the installed app.
set -euo pipefail
kept=$HOME/.recalldiscord-certificate.p12
[ ! -e "$kept" ] || { echo "$kept already exists: nothing done.";exit 1;}
folder=$(mktemp -d);trap 'rm -rf "$folder"' EXIT
password=$(openssl rand -hex 24)
cat > "$folder/certificate.cnf" <<CNF
[req]
distinguished_name=name
x509_extensions=use
prompt=no
[name]
CN=RecallDiscord
[use]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -keyout "$folder/key" -out "$folder/certificate" -config "$folder/certificate.cnf" 2>/dev/null
legacy=$(openssl version | grep -q LibreSSL || echo -legacy)
openssl pkcs12 -export $legacy -inkey "$folder/key" -in "$folder/certificate" -out "$kept" -passout "pass:$password"
chmod 600 "$kept"
base64 -i "$kept" | gh secret set FORK_CERT_P12 --repo ayyneya/recall
printf %s "$password" | gh secret set FORK_CERT_PASSWORD --repo ayyneya/recall
security add-generic-password -U -a "$USER" -s RecallDiscordCertificate -w "$password"
echo "Done. The certificate is on the fork, with a copy at $kept and its password in your login keychain (RecallDiscordCertificate)."
