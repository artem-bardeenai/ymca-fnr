#!/bin/bash
# Generates dist/index.html by encrypting the sheet URLs with the team password.
#
# Usage: ./build.sh <password> <csv_export_url> <sheet_edit_url>
#
# Example:
#   ./build.sh gopirates \
#     'https://docs.google.com/spreadsheets/d/1yYN.../export?format=csv&gid=1352731412' \
#     'https://docs.google.com/spreadsheets/d/1yYN.../edit?gid=1352731412#gid=1352731412'

set -euo pipefail

PASSWORD="${1:?Usage: $0 <password> <csv_url> <edit_url>}"
CSV_URL="${2:?Missing CSV export URL}"
EDIT_URL="${3:?Missing sheet edit URL}"

# Encrypt using Node's crypto (AES-256-GCM, PBKDF2 key derivation).
# Output layout: iv (12 bytes) + ciphertext + authTag (16 bytes)
# WebCrypto's AES-GCM decrypt expects iv separately and ciphertext+tag concatenated,
# so we output: iv (12) + ciphertext + tag (16). The browser slices iv off the front
# and passes the rest (ciphertext+tag) to decrypt.
encrypt() {
  node -e "
    const crypto = require('crypto');
    const pw = process.argv[1];
    const text = process.argv[2];
    crypto.pbkdf2(pw, 'pirates', 100000, 32, 'sha256', (err, key) => {
      if (err) { console.error(err); process.exit(1); }
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
      const enc = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
      const tag = cipher.getAuthTag();
      // iv + ciphertext + tag  (WebCrypto expects tag appended to ciphertext)
      const result = Buffer.concat([iv, enc, tag]);
      console.log(result.toString('base64'));
    });
  " "$1" "$2"
}

ENC_CSV=$(encrypt "$PASSWORD" "$CSV_URL")
ENC_EDIT=$(encrypt "$PASSWORD" "$EDIT_URL")
PW_HASH=$(printf '%s' "$PASSWORD" | shasum -a 256 | cut -d' ' -f1)

sed \
  -e "s|%%ENC_CSV_URL%%|${ENC_CSV}|g" \
  -e "s|%%ENC_EDIT_URL%%|${ENC_EDIT}|g" \
  -e "s|b7e88684a8ca4218479e815ed6546d69ec1d2fa16de5e7b5d6a1f05f87c74fbf|${PW_HASH}|g" \
  template.html > index.html

echo "Built index.html with encrypted URLs."
