#!/usr/bin/env bash
# Install a merged SDL controller DB into PCSX2's user data directory.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCSX2_DIR="${PCSX2_DIR:-$HOME/Library/Application Support/PCSX2}"
PCSX2_BUNDLE_DB="${PCSX2_BUNDLE_DB:-/Applications/PCSX2.app/Contents/Resources/game_controller_db.txt}"
OJD_DB="$ROOT/Resources/SDL/openjoystickdriver.gamecontrollerdb.txt"
DEST="$PCSX2_DIR/game_controller_db.txt"
GUID="0300f88c4a4f00004844000008040000"
OLD_GUID="0300f88c4a4f00004744000008040000"

if [[ ! -f "$PCSX2_BUNDLE_DB" ]]; then
  echo "ERROR: PCSX2 bundled controller DB not found: $PCSX2_BUNDLE_DB" >&2
  exit 2
fi

if [[ ! -f "$OJD_DB" ]]; then
  echo "ERROR: OpenJoystickDriver SDL mapping not found: $OJD_DB" >&2
  exit 2
fi

mkdir -p "$PCSX2_DIR"
if [[ -f "$DEST" ]]; then
  cp "$DEST" "$DEST.ojd-backup-$(date +%Y%m%d%H%M%S)"
fi

OLD_GUID="$OLD_GUID" GUID="$GUID" perl -e '
  use Fcntl qw(O_CREAT O_TRUNC O_WRONLY);
  my ($source, $mapping, $dest) = @ARGV;
  open(my $in, chr(60), $source) or die "open $source: $!";
  sysopen(my $out, $dest, O_CREAT | O_TRUNC | O_WRONLY, 0644) or die "open $dest: $!";
  while (my $line = <$in>) {
    next if $line =~ /\Q$ENV{OLD_GUID}\E/;
    next if $line =~ /\Q$ENV{GUID}\E/;
    print {$out} $line;
  }
  print {$out} "\n# OpenJoystickDriver virtual gamepad\n";
  open(my $map, chr(60), $mapping) or die "open $mapping: $!";
  while (my $line = <$map>) {
    next if $line =~ /^\s*#/;
    next if $line =~ /^\s*$/;
    print {$out} $line;
  }
' "$PCSX2_BUNDLE_DB" "$OJD_DB" "$DEST"

echo "Installed merged PCSX2 SDL controller DB:"
echo "  $DEST"
grep -n "$GUID" "$DEST"
