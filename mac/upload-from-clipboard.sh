#!/bin/bash
# upload-from-clipboard — sube file/img del clipboard a corhild + clipboard=@path
# Optimizado para velocidad. Si clipboard es texto, exit 0 sin tocar clipboard.

set -uo pipefail
export PATH="/Users/gevensa/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

WEBDAV_DIR="/Volumes/files/tmp"
SERVER="corhild"
REMOTE_DIR="/home/geison/tmp"
TS=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp /tmp/upload-XXXX)
trap "rm -f $TMP" EXIT

slugify() {
    echo "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9.' '-' \
        | sed -E 's/-+/-/g; s/^-+//; s/-+$//'
}

LOCAL_FILE=""
FILENAME=""

# 1. Imagen — detecta GIF antes de pngpaste (que convierte todo a PNG)
if pngpaste "$TMP" 2>/dev/null && [ "$(wc -c < "$TMP")" -gt 100 ]; then
    CLIP_TYPES=$(osascript -e 'try
set t to (clipboard info)
set out to ""
repeat with i in t
set out to out & (item 1 of i as string) & ","
end repeat
return out
end try' 2>/dev/null)
    if echo "$CLIP_TYPES" | grep -qi "GIFf\|com.compuserve.gif"; then
        # Re-extraer como GIF nativo
        osascript >/dev/null 2>&1 <<OSASCRIPT
try
set gifData to the clipboard as «class GIFf»
set f to open for access POSIX file "$TMP" with write permission
set eof f to 0
write gifData to f
close access f
end try
OSASCRIPT
        FILENAME="${TS}-image.gif"
    else
        FILENAME="${TS}-screenshot.png"
    fi
    LOCAL_FILE="$TMP"
else
    # 2. Archivo desde Finder
    FINDER_PATH=$(osascript -e 'try
the clipboard as «class furl»
POSIX path of result
end try' 2>/dev/null | tr -d '\n')
    if [ -n "$FINDER_PATH" ] && [ -f "$FINDER_PATH" ]; then
        BASE=$(basename "$FINDER_PATH")
        NAME=$(slugify "${BASE%.*}")
        EXT=$(slugify "${BASE##*.}")
        [ -z "$NAME" ] && NAME="file"
        FILENAME="${TS}-${NAME}.${EXT}"
        cp "$FINDER_PATH" "$TMP"
        LOCAL_FILE="$TMP"
    fi
fi

# Sin archivo → texto en clipboard, exit OK sin tocar nada (daemon pega texto normal)
[ -z "$LOCAL_FILE" ] && exit 0

# Upload via WebDAV preferido, scp fallback
if [ -d "$WEBDAV_DIR" ] && cp "$LOCAL_FILE" "${WEBDAV_DIR}/${FILENAME}" 2>/dev/null; then
    :
elif ! scp -q -o ConnectTimeout=5 "$LOCAL_FILE" "${SERVER}:${REMOTE_DIR}/${FILENAME}" 2>/dev/null; then
    exit 1
fi

# @path al clipboard
printf '%s' "@${REMOTE_DIR}/${FILENAME}" | pbcopy
