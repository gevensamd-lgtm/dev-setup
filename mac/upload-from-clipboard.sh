#!/bin/bash
# upload-from-clipboard — sube cualquier archivo/imagen del clipboard a corhild
# Flujos detectados:
#   1. Imagen (PNG, GIF nativo)
#   2. Archivo desde Finder (Cmd+C) — cualquier tipo: mp4, zip, docx, mov, etc.
#   3. PDF copiado desde Preview/Safari (data)
#   4. Texto que es ruta absoluta a archivo existente
# Si clipboard solo es texto → exit 0 (daemon pega texto normal)

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

handle_finder_file() {
    local path="$1"
    local base=$(basename "$path")
    local name=$(slugify "${base%.*}")
    local ext=$(slugify "${base##*.}")
    [ "$ext" = "$(slugify "$base")" ] && ext="bin"
    [ -z "$name" ] && name="file"
    FILENAME="${TS}-${name}.${ext}"
    cp "$path" "$TMP"
    LOCAL_FILE="$TMP"
}

LOCAL_FILE=""
FILENAME=""

# 1. Imagen (PNG default, GIF si nativo)
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
fi

# 2. Archivo desde Finder (cualquier tipo)
if [ -z "$LOCAL_FILE" ]; then
    FINDER_PATH=$(osascript -e 'try
the clipboard as «class furl»
POSIX path of result
end try' 2>/dev/null | tr -d '\n')
    if [ -n "$FINDER_PATH" ] && [ -f "$FINDER_PATH" ]; then
        handle_finder_file "$FINDER_PATH"
    fi
fi

# 3. PDF desde Preview/Safari (clipboard data)
if [ -z "$LOCAL_FILE" ]; then
    CLIP_TYPES="${CLIP_TYPES:-$(osascript -e 'try
set t to (clipboard info)
set out to ""
repeat with i in t
set out to out & (item 1 of i as string) & ","
end repeat
return out
end try' 2>/dev/null)}"
    if echo "$CLIP_TYPES" | grep -qi "pdf"; then
        osascript >/dev/null 2>&1 <<OSASCRIPT
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

# 4. Texto que es ruta a archivo existente
if [ -z "$LOCAL_FILE" ]; then
    PBTEXT=$(pbpaste 2>/dev/null | head -1)
    if [ -n "$PBTEXT" ] && [ -f "$PBTEXT" ]; then
        handle_finder_file "$PBTEXT"
    fi
fi

# Sin archivo → texto, exit OK (daemon pega texto normal)
[ -z "$LOCAL_FILE" ] && exit 0

# Upload WebDAV preferido, scp fallback
if [ -d "$WEBDAV_DIR" ] && cp "$LOCAL_FILE" "${WEBDAV_DIR}/${FILENAME}" 2>/dev/null; then
    :
elif ! scp -q -o ConnectTimeout=5 "$LOCAL_FILE" "${SERVER}:${REMOTE_DIR}/${FILENAME}" 2>/dev/null; then
    exit 1
fi

# @path al clipboard
printf '%s' "@${REMOTE_DIR}/${FILENAME}" | pbcopy
