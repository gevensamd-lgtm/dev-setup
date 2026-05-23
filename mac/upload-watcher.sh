#!/bin/bash
# upload-watcher — vigila el clipboard de macOS y sube archivos/imágenes a corhild
# Al subir, reemplaza el clipboard por @/home/geison/tmp/<archivo> listo para Cmd+V
#
# Detecta:
#  - Archivos copiados desde Finder (Cmd+C sobre archivo): cualquier tipo (PDF/zip/png/docx/...)
#  - Imágenes en clipboard (screenshots Cmd+Shift+4, CleanShot X, etc.)
#  - PDFs copiados desde Preview/Safari
# Ignora: texto plano, @paths previos (no entra en bucle), clipboards vacíos

set -uo pipefail

SERVER="corhild"
REMOTE_DIR="/home/geison/tmp"
POLL_INTERVAL=0.5
LAST_HASH=""

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Slugifica: minúsculas, espacios y símbolos → guiones, sin acentos, colapsa guiones
slugify() {
    echo "$1" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9.' '-' \
        | sed -E 's/-+/-/g; s/^-+//; s/-+$//'
}

# Hash del clipboard actual (combina tipos + tamaño + primeros bytes para diferenciar)
clipboard_hash() {
    {
        osascript -e 'try
            (clipboard info) as string
        end try' 2>/dev/null
        pbpaste 2>/dev/null | head -c 200
    } | md5
}

# Sube y devuelve la ruta remota, o vacío si nada que subir
try_upload() {
    local tmp
    tmp=$(mktemp /tmp/clipwatch-XXXX)
    # cleanup on return: dejamos $tmp y caller borra
    local ts ext name filename
    ts=$(date +%Y%m%d-%H%M%S)
    local src=""
    local detected_type=""

    # 1. Archivo desde Finder
    local finder_path
    finder_path=$(osascript 2>/dev/null <<'EOF'
try
    set f to the clipboard as «class furl»
    POSIX path of f
end try
EOF
)
    finder_path=$(echo "$finder_path" | tr -d '\n')
    if [ -n "$finder_path" ] && [ -f "$finder_path" ]; then
        src="finder"
        local base
        base=$(basename "$finder_path")
        name="${base%.*}"
        ext="${base##*.}"
        [ "$ext" = "$base" ] && ext="bin"
        name=$(slugify "$name")
        ext=$(slugify "$ext")
        [ -z "$name" ] && name="file"
        filename="${ts}-${name}.${ext}"
        cp "$finder_path" "$tmp"
        detected_type="finder:$base"
    fi

    # 2. Imagen
    if [ -z "$src" ]; then
        if pngpaste "$tmp" 2>/dev/null && [ "$(wc -c < "$tmp")" -gt 100 ]; then
            src="image"
            filename="${ts}-screenshot.png"
            detected_type="image"
        fi
    fi

    # 3. PDF
    if [ -z "$src" ]; then
        local clip_types
        clip_types=$(osascript 2>/dev/null <<'EOF'
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
        if echo "$clip_types" | grep -qi "pdf"; then
            osascript 2>/dev/null <<OSASCRIPT
try
    set pdfData to the clipboard as «class PDF »
    set f to open for access POSIX file "$tmp" with write permission
    set eof f to 0
    write pdfData to f
    close access f
end try
OSASCRIPT
            if [ "$(wc -c < "$tmp")" -gt 100 ]; then
                src="pdf"
                filename="${ts}-document.pdf"
                detected_type="pdf"
            fi
        fi
    fi

    if [ -z "$src" ]; then
        rm -f "$tmp"
        return 1
    fi

    local remote_path="${REMOTE_DIR}/${filename}"
    if ! scp -q -o ConnectTimeout=10 "$tmp" "${SERVER}:${remote_path}" 2>/dev/null; then
        osascript -e 'display notification "scp falló — revisa SSH" with title "Upload error"' 2>/dev/null
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"

    local ref="@${remote_path}"
    printf '%s' "$ref" | pbcopy
    osascript -e "display notification \"$filename — Cmd+V para pegar\" with title \"Upload ✓ ($detected_type)\"" 2>/dev/null
    log "uploaded $detected_type → $remote_path"
    return 0
}

log "watcher iniciado (poll ${POLL_INTERVAL}s, server $SERVER:$REMOTE_DIR)"

while true; do
    h=$(clipboard_hash)
    if [ "$h" != "$LAST_HASH" ] && [ -n "$h" ]; then
        # Solo sube si el clipboard NO es ya un @path (evita bucle)
        current=$(pbpaste 2>/dev/null | head -c 100)
        case "$current" in
            @/home/geison/tmp/*)
                ;;
            *)
                if try_upload; then
                    # tras subir, recalculamos hash con el nuevo @path para no re-disparar
                    h=$(clipboard_hash)
                fi
                ;;
        esac
        LAST_HASH="$h"
    fi
    sleep "$POLL_INTERVAL"
done
