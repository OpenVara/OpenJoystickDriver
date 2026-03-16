#!/usr/bin/env bash
# Diagnostic: check that provisioning profile certs match the signing identity.
# Run this before/after regenerating profiles at developer.apple.com to verify
# that profiles embed the correct Developer ID Application certificate.
set -euo pipefail

# Force release so lib.sh selects the _DevID profile variants
export OJD_ENV="release"
source "$(dirname "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Collect data
# ---------------------------------------------------------------------------
keychain_sha1=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
keychain_serial=$(security find-certificate -c "Developer ID Application" -p 2>/dev/null \
  | openssl x509 -noout -serial 2>/dev/null \
  | sed 's/serial=//')
keychain_expiry=$(security find-certificate -c "Developer ID Application" -p 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null \
  | sed 's/notAfter=//')
keychain_name=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | sed 's/.*"\(.*\)"/\1/')

# Which .cer file in ~/Documents/Certificates/ matches the keychain?
keychain_cer_file=""
for f in ~/Documents/Certificates/developerID_application*.cer; do
  [[ -f "$f" ]] || continue
  sha1=$(openssl x509 -inform DER -in "$f" -noout -fingerprint -sha1 2>/dev/null \
    | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
  if [[ "$sha1" == "$keychain_sha1" ]]; then
    keychain_cer_file="$f"
    break
  fi
done

# Check each release profile
mismatched_profiles=()
for label_and_path in "GUI|$GUI_PROFILE" "Daemon|$DAEMON_PROFILE"; do
  label="${label_and_path%%|*}"
  path="${label_and_path#*|}"
  if [[ ! -f "$path" ]]; then
    mismatched_profiles+=("$label|$path|MISSING|")
    continue
  fi
  tmpder=$(mktemp)
  security cms -D -i "$path" 2>/dev/null \
    | plutil -extract DeveloperCertificates.0 raw -o - - \
    | base64 -d > "$tmpder" 2>/dev/null
  psha1=$(openssl x509 -inform DER -in "$tmpder" -noout -fingerprint -sha1 2>/dev/null \
    | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
  pserial=$(openssl x509 -inform DER -in "$tmpder" -noout -serial 2>/dev/null \
    | sed 's/serial=//')
  rm -f "$tmpder"
  if [[ "$psha1" != "$keychain_sha1" ]]; then
    mismatched_profiles+=("$label|$path|$psha1|$pserial")
  fi
done

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo "Signing certificate in keychain:"
echo "  $keychain_name"
echo "  Expires: $keychain_expiry"
if [[ -n "$keychain_cer_file" ]]; then
  echo "  File:    $(basename "$keychain_cer_file")"
else
  echo "  File:    (no matching .cer found in ~/Documents/Certificates/)"
fi
echo ""

if [[ ${#mismatched_profiles[@]} -eq 0 ]]; then
  echo "All provisioning profiles match the keychain certificate."
  echo ""
  echo "  [GUI]    $(basename "$GUI_PROFILE")"
  echo "  [Daemon] $(basename "$DAEMON_PROFILE")"
  echo ""
  echo "No action needed."
  exit 0
fi

echo "${#mismatched_profiles[@]} profile(s) need to be regenerated:"
echo ""
for entry in "${mismatched_profiles[@]}"; do
  label="${entry%%|*}"; rest="${entry#*|}"
  path="${rest%%|*}"; rest="${rest#*|}"
  status="${rest%%|*}"; pserial="${rest#*|}"
  echo "  [$label] $(basename "$path")"
  if [[ "$status" == "MISSING" ]]; then
    echo "    File not found at: $path"
  else
    echo "    Currently embeds cert serial: $pserial"
    echo "    Needs to embed cert serial:   $keychain_serial"
  fi

  # Show the entitlements/capabilities from the current profile
  if [[ -f "$path" ]]; then
    echo ""
    echo "    Capabilities to enable (copy these exactly):"
    security cms -D -i "$path" 2>/dev/null \
      | plutil -extract Entitlements xml1 -o - - 2>/dev/null \
      | grep '<key>' | sed 's|.*<key>||;s|</key>||' \
      | while read -r ent; do
        # Skip boilerplate keys that are set automatically
        case "$ent" in
          com.apple.application-identifier|com.apple.developer.team-identifier|keychain-access-groups)
            continue ;;
        esac
        # Show the value alongside the key
        val=$(security cms -D -i "$path" 2>/dev/null \
          | plutil -extract Entitlements xml1 -o - - 2>/dev/null \
          | plutil -extract "$ent" raw -o - - 2>/dev/null || echo "<true>")
        echo "      - $ent = $val"
      done
  fi
  echo ""
done

echo "HOW TO FIX:"
echo ""
echo "  1. Open https://developer.apple.com/account/resources/profiles/list"
echo ""
echo "  2. For each profile above, click it (or create new):"
echo "     - Type: Developer ID Application"
echo "     - App IDs to use:"
for entry in "${mismatched_profiles[@]}"; do
  label="${entry%%|*}"
  if [[ "$label" == "GUI" ]]; then
    echo "       GUI:    com.openjoystickdriver"
  else
    echo "       Daemon: com.openjoystickdriver.daemon"
  fi
done
echo "     - Enable the capabilities listed above for each profile"
echo ""
echo "  3. When asked to select a certificate, pick the one expiring:"
echo "     $keychain_expiry"
echo "     (On the Apple website this shows as the expiry date next to the cert name)"
echo ""
echo "     Full identity: $keychain_name"
echo "     Expires: $keychain_expiry"
if [[ -n "$keychain_cer_file" ]]; then
  echo "     Local file: $(basename "$keychain_cer_file")"
fi
echo ""
echo "  4. Download and copy the .provisionprofile files to:"
echo "     ~/Library/MobileDevice/Provisioning Profiles/"
for entry in "${mismatched_profiles[@]}"; do
  label="${entry%%|*}"; rest="${entry#*|}"
  path="${rest%%|*}"
  echo "     as: $(basename "$path")"
done
echo ""
echo "  5. Re-run this script to verify: ./scripts/check-profiles.sh"
