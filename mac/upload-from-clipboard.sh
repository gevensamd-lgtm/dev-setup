#!/bin/bash
# upload-from-clipboard — sube cualquier archivo/imagen del clipboard a corhild
# Prioridad:
#   1. Archivo desde Finder (Cmd+C en archivo) — TOMA EL ARCHIVO REAL no su ícono
#   2. Imagen del clipboard (screenshot/CleanShot/copy image desde browser)
#      - GIF nativo si com.compuserve.gif presente
#      - PNG en otros casos via pngpaste
#   3. PDF copiado desde Preview/Safari (clipboard data)
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

handle_file() {
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

# 1. Archivo Finder PRIMERO — evita capturar el ícono en vez del archivo
FINDER_PATH=$(osascript -e 'try
the clipboard as «class furl»
POSIX path of result
end try' 2>/dev/null | tr -d '\n')
if [ -n "$FINDER_PATH" ] && [ -f "$FINDER_PATH" ]; then
    handle_file "$FINDER_PATH"
fi

# 2. Imagen del clipboard (solo si NO había archivo Finder)
if [ -z "$LOCAL_FILE" ]; then
    IMG_KIND=$(osascript -l JavaScript <<'JXA' 2>/dev/null
ObjC.import('AppKit');
var pb = $.NSPasteboard.generalPasteboard;
var types = ObjC.deepUnwrap(pb.types) || [];
var has = (t) => types.indexOf(t) !== -1;
if (has('com.compuserve.gif')) { 'gif'; }
else if (has('public.png') || has('public.tiff') || has('com.apple.icns')) { 'png'; }
else { 'none'; }
JXA
)
    if [ "$IMG_KIND" = "gif" ]; then
        osascript -l JavaScript >/dev/null 2>&1 <<JXA
ObjC.import('AppKit');
var pb = $.NSPasteboard.generalPasteboard;
var data = pb.dataForType('com.compuserve.gif');
if (data && data.length > 0) {
    data.writeToFileAtomically('$TMP', true);
}
JXA
        if [ -s "$TMP" ] && [ "$(head -c 4 "$TMP" 2>/dev/null)" = "GIF8" ]; then
            FILENAME="${TS}-image.gif"
            LOCAL_FILE="$TMP"
        fi
    elif [ "$IMG_KIND" = "png" ]; then
        if pngpaste "$TMP" 2>/dev/null && [ "$(wc -c < "$TMP")" -gt 100 ]; then
            FILENAME="${TS}-screenshot.png"
            LOCAL_FILE="$TMP"
        fi
    fi
fi

# 3. PDF desde Preview/Safari (clipboard data)
if [ -z "$LOCAL_FILE" ]; then
    CLIP_TYPES=$(osascript -e 'try
set t to (clipboard info)
set out to ""
repeat with i in t
set out to out & (item 1 of i as string) & ","
end repeat
return out
end try' 2>/dev/null)
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
        handle_file "$PBTEXT"
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
