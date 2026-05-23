#!/bin/bash
# upload — cualquier archivo/imagen/PDF del clipboard o Finder → corhild → auto-tipea @path en VS Code
# Uso: upload [nombre]   Atajo: Cmd+Shift+U en VS Code

set -euo pipefail

SERVER="corhild"
REMOTE_DIR="/home/geison/tmp"
TS=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp /tmp/upload-XXXX)
trap "rm -f $TMP" EXIT

LOCAL_FILE=""
FILENAME=""

# Slugifica: minúsculas, espacios/símbolos → guiones, sin acentos
slugify() {
    echo "$1" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9.' '-' \
        | sed -E 's/-+/-/g; s/^-+//; s/-+$//'
}

# 0. $1 es una ruta a archivo (drag desde Finder al terminal, o `upload ~/foo.pdf`)
if [ -n "${1:-}" ] && [ -f "$1" ]; then
    BASENAME=$(basename "$1")
    NAME="${BASENAME%.*}"
    EXT="${BASENAME##*.}"
    [ "$EXT" = "$BASENAME" ] && EXT="bin"
    NAME=$(slugify "$NAME")
    EXT=$(slugify "$EXT")
    [ -z "$NAME" ] && NAME="file"
    FILENAME="${TS}-${NAME}.${EXT}"
    cp "$1" "$TMP"
    LOCAL_FILE="$TMP"
else
    NAME=$(slugify "${1:-file}")
    [ -z "$NAME" ] && NAME="file"
fi

# 1. Archivo copiado desde Finder (Cmd+C) — cubre TODO tipo: PDF, zip, docx, png, etc.
if [ -z "$LOCAL_FILE" ]; then
    FINDER_PATH=$(osascript 2>/dev/null << 'EOF'
try
    set f to the clipboard as «class furl»
    POSIX path of f
end try
EOF
)
    FINDER_PATH=$(echo "$FINDER_PATH" | tr -d '\n')
    if [ -n "$FINDER_PATH" ] && [ -f "$FINDER_PATH" ]; then
        BASE=$(basename "$FINDER_PATH")
        FNAME="${BASE%.*}"
        EXT="${BASE##*.}"
        [ "$EXT" = "$BASE" ] && EXT="bin"
        FNAME=$(slugify "$FNAME")
        EXT=$(slugify "$EXT")
        [ -z "$FNAME" ] && FNAME="$NAME"
        FILENAME="${TS}-${FNAME}.${EXT}"
        cp "$FINDER_PATH" "$TMP"
        LOCAL_FILE="$TMP"
    fi
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

# Contexto: VS Code auto-tipea local; Warp/Terminal/iTerm/SSH copian al clipboard
case "${TERM_PROGRAM:-}" in
    vscode)
        # VS Code: limpiar clipboard y auto-tipear en la ventana de Code
        printf '' | pbcopy
        osascript -e "display notification \"$FILENAME\" with title \"Upload OK ✓ auto-pegado en VS Code\"" 2>/dev/null
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
        ;;
    *)
        # Warp / Terminal / iTerm / SSH remoto: dejar @path en clipboard, usuario pega con Cmd+V
        printf '%s' "$CLAUDE_REF" | pbcopy
        osascript -e "display notification \"$CLAUDE_REF — pega con Cmd+V\" with title \"Upload OK ✓ en clipboard\"" 2>/dev/null
        echo "$CLAUDE_REF"
        ;;
esac
