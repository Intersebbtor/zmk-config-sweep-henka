#!/usr/bin/env bash
# Flash sweep half from latest CI build of HEAD.
# Usage: flash.sh [left|right]   (default: left)
set -euo pipefail

SIDE="${1:-left}"
[[ "$SIDE" == "left" || "$SIDE" == "right" ]] || { echo "Usage: $0 [left|right]"; exit 1; }

VOL=/Volumes/NICENANO
WAIT_MOUNT=300

cd "$(dirname "$0")/.."
SHA=$(git rev-parse HEAD)
echo "Commit: $(git log --oneline -1)"

# Run for HEAD finden. Nach Push kann es kurz dauern.
RUN=""
for _ in $(seq 1 30); do
  RUN=$(gh run list --commit "$SHA" -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  [[ -n "$RUN" ]] && break
  sleep 2
done
[[ -n "$RUN" ]] || { echo "Kein Action-Run fuer $SHA. Gepusht?"; exit 1; }

echo "Run $RUN. Warte auf Build..."
gh run watch "$RUN" --exit-status --interval 10 >/dev/null || { echo "Build fehlgeschlagen."; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
gh run download "$RUN" -D "$TMP"
UF2=$(find "$TMP" -name "*${SIDE}*.uf2" | head -1)
[[ -n "$UF2" ]] || { echo "Keine ${SIDE}-UF2 im Artefakt."; exit 1; }
echo "Firmware: $(basename "$UF2")"

printf '\a'
echo ">>> ${SIDE} Haelfte in Bootloader setzen (L3 > tog 4 > bootloader, oder 2x Reset)."
for i in $(seq 1 "$WAIT_MOUNT"); do
  [[ -d "$VOL" ]] && break
  sleep 1
  [[ $i -eq $WAIT_MOUNT ]] && { echo "Timeout, kein $VOL."; exit 1; }
done
sleep 1

# macOS meldet oft I/O-Fehler, weil der Bootloader neu startet bevor cp fertig ist.
if /bin/cp "$UF2" "$VOL/" 2>/dev/null; then
  echo "Geflasht."
else
  sleep 2
  if [[ -d "$VOL" ]]; then
    echo "Kopieren fehlgeschlagen, $VOL noch da."; exit 1
  fi
  echo "Geflasht (Laufwerk nach Neustart weg, normal)."
fi
