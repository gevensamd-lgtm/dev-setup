#!/bin/bash
# upload — cualquier archivo/imagen/PDF del clipboard o Finder → corhild → auto-tipea @path en VS Code
# Uso: upload [nombre]   Atajo: Cmd+Shift+U en VS Code

set -euo pipefail

SERVER="corhild"
REMOTE_DIR="/home/geison/tmp"
NAME="${1:-file}"
TS=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp /tmp/upload-XXXX)
trap "rm -f $TMP" EXIT

LOCAL_FILE=""
FILENAME=""

# 1. Archivo copiado desde Finder (Cmd+C) — cubre TODO tipo: PDF, zip, docx, png, etc.
FINDER_PATH=$(osascript 2>/dev/null << 'EOF'
try
    set f to the clipboard as «class furl»
    POSIX path of f
end try
EOF
)
FINDER_PATH=$(echo "$FINDER_PATH" | tr -d '\n ')
if [ -n "$FINDER_PATH" ] && [ -f "$FINDER_PATH" ]; then
    EXT="${FINDER_PATH##*.}"
    [ -z "$EXT" ] || [ "$EXT" = "$FINDER_PATH" ] && EXT="bin"
    FILENAME="${TS}-${NAME}.${EXT}"
    cp "$FINDER_PATH" "$TMP"
    LOCAL_FILE="$TMP"
fi

# 2. Imagen del clipboard (screenshot Cmd+Shift+4 o imagen copiada)
if [ -z "$LOCAL_FILE" ]; then
    if pngpaste "$TMP" 2>/dev/null && [ "$(wc -c < "$TMP")" -gt 100 ]; then
        FILENAME="${TS}-${NAME}.png"
        LOCAL_FILE="$TMP"
    fi
fi

# 3. PDF copiado desde Preview/Safari/navegador (datos PDF en clipboard)
if [ -z "$LOCAL_FILE" ]; then
    CLIP_TYPES=$(osascript 2>/dev/null << 'EOF'
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
        osascript 2>/dev/null << OSASCRIPT
try
    set pdfData to the clipboard as «class PDF »
    set f to open for access POSIX file "$TMP" with write permission
    set eof f to 0
    write pdfData to f
    close access f
end try
OSASCRIPT
        if [ "$(wc -c < "$TMP")" -gt 100 ]; then
            FILENAME="${TS}-${NAME}.pdf"
            LOCAL_FILE="$TMP"
        fi
    fi
fi

# 4. Cualquier otro dato binario del clipboard (RTF, HTML, etc.)
if [ -z "$LOCAL_FILE" ]; then
    CLIP_TYPES=$(osascript 2>/dev/null << 'EOF'
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
    # Detectar extensión según tipo MIME del clipboard
    EXT="bin"
    echo "$CLIP_TYPES" | grep -qi "rtf"  && EXT="rtf"
    echo "$CLIP_TYPES" | grep -qi "html" && EXT="html"
    echo "$CLIP_TYPES" | grep -qi "tiff" && EXT="tiff"

    # Intentar leer datos crudos del clipboard via pbpaste (texto)
    PBDATA=$(pbpaste 2>/dev/null)
    if [ -n "$PBDATA" ]; then
        FILENAME="${TS}-${NAME}.txt"
        printf '%s' "$PBDATA" > "$TMP"
        LOCAL_FILE="$TMP"
    fi
fi

if [ -z "$LOCAL_FILE" ]; then
    osascript -e 'display notification "Copia un archivo en Finder, toma screenshot (Cmd+Shift+4) o copia un PDF" with title "Upload: sin archivo"' 2>/dev/null
    exit 1
fi

REMOTE_PATH="${REMOTE_DIR}/${FILENAME}"

# SCP al servidor
if ! scp -q "$LOCAL_FILE" "${SERVER}:${REMOTE_PATH}" 2>/dev/null; then
    osascript -e 'display notification "No se pudo conectar a corhild" with title "Upload: error"' 2>/dev/null
    exit 1
fi

CLAUDE_REF="@${REMOTE_PATH}"

# Limpiar clipboard antes de tipear (evita auto-paste de VS Code)
printf '' | pbcopy

# Notificación macOS
osascript -e "display notification \"$FILENAME\" with title \"Upload OK ✓ auto-pegado\"" 2>/dev/null

# Auto-tipear en VS Code — nunca va al clipboard
osascript 2>/dev/null << APPLESCRIPT
delay 0.3
tell application "System Events"
    tell process "Code"
        set frontmost to true
    end tell
    delay 0.4
    keystroke "${CLAUDE_REF}"
end tell
APPLESCRIPT
