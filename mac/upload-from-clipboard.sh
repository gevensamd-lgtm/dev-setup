#!/bin/bash
# upload-from-clipboard — invocado por el Shortcut Cmd+Shift+V
# Sube clipboard a corhild, copia @path al clipboard, muestra notificación.
# El usuario luego hace Cmd+V (paste normal) en la app donde quiera pegar.

set -uo pipefail

# Asegurar PATH para que encuentre pngpaste/scp aunque Shortcuts.app no herede tu shell
export PATH="/Users/gevensa/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

SERVER="corhild"
REMOTE_DIR="/home/geison/tmp"
TS=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp /tmp/upload-XXXX)
trap "rm -f $TMP" EXIT

slugify() {
    echo "$1" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9.' '-' \
        | sed -E 's/-+/-/g; s/^-+//; s/-+$//'
}

LOCAL_FILE=""
FILENAME=""

# 1. Archivo copiado desde Finder
FINDER_PATH=$(osascript 2>/dev/null <<'EOF'
try
    set f to the clipboard as «class furl»
    POSIX path of f
end try
EOF
)
FINDER_PATH=$(echo "$FINDER_PATH" | tr -d '\n')
if [ -n "$FINDER_PATH" ] && [ -f "$FINDER_PATH" ]; then
    BASE=$(basename "$FINDER_PATH")
    NAME=$(slugify "${BASE%.*}")
    EXT=$(slugify "${BASE##*.}")
    [ "$EXT" = "${BASE##*.}" ] && [ "$EXT" = "$(slugify "$BASE")" ] && EXT="bin"
    [ -z "$NAME" ] && NAME="file"
    FILENAME="${TS}-${NAME}.${EXT}"
    cp "$FINDER_PATH" "$TMP"
    LOCAL_FILE="$TMP"
fi

# 2. Imagen en clipboard (screenshot, CleanShot, etc.)
if [ -z "$LOCAL_FILE" ]; then
    if pngpaste "$TMP" 2>/dev/null && [ "$(wc -c < "$TMP")" -gt 100 ]; then
        FILENAME="${TS}-screenshot.png"
        LOCAL_FILE="$TMP"
    fi
fi

# 3. PDF en clipboard
if [ -z "$LOCAL_FILE" ]; then
    CLIP_TYPES=$(osascript 2>/dev/null <<'EOF'
try
    set theTypes to (clipboard info)
    set out to ""
    repeat with t in theTypes
        set out to out & (item 1 of t as string) & ","
    end repeat
    return out
end try
EOF
)
    if echo "$CLIP_TYPES" | grep -qi "pdf"; then
        osascript 2>/dev/null <<OSASCRIPT
try
    set pdfData to the clipboard as «class PDF »
    set f to open for access POSIX file "$TMP" with write permission
    set eof f to 0
    write pdfData to f
    close access f
end try
OSASCRIPT
        if [ "$(wc -c < "$TMP")" -gt 100 ]; then
            FILENAME="${TS}-document.pdf"
            LOCAL_FILE="$TMP"
        fi
    fi
fi

if [ -z "$LOCAL_FILE" ]; then
    osascript -e 'display notification "Copia un archivo/imagen/PDF primero" with title "Upload: clipboard vacío"' 2>/dev/null
    exit 1
fi

REMOTE_PATH="${REMOTE_DIR}/${FILENAME}"

if ! scp -q -o ConnectTimeout=10 "$LOCAL_FILE" "${SERVER}:${REMOTE_PATH}" 2>/dev/null; then
    osascript -e 'display notification "scp falló — revisa SSH a corhild" with title "Upload: error"' 2>/dev/null
    exit 1
fi

# @path al clipboard — el usuario lo pega con Cmd+V donde quiera
printf '%s' "@${REMOTE_PATH}" | pbcopy

osascript -e "display notification \"$FILENAME — Cmd+V para pegar\" with title \"Upload ✓\"" 2>/dev/null
echo "@${REMOTE_PATH}"
