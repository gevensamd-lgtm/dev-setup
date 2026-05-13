# upload.ps1 — clipboard (imagen o archivo) → corhild → auto-tipea @path en VS Code
param([string]$Name = "screenshot")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SERVER     = "corhild"
$REMOTE_DIR = "/home/geison/tmp"
$TS         = Get-Date -Format "yyyyMMdd-HHmmss"
$TMP        = [System.IO.Path]::GetTempPath()
$LOCAL_FILE = ""
$FILENAME   = ""

# 1. Imagen del clipboard (Win+Shift+S o PrintScreen)
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($null -ne $img) {
    $FILENAME   = "$TS-$Name.png"
    $LOCAL_FILE = Join-Path $TMP $FILENAME
    $img.Save($LOCAL_FILE, [System.Drawing.Imaging.ImageFormat]::Png)
}

# 2. Archivo copiado desde Explorer (Ctrl+C sobre un archivo)
if (-not $LOCAL_FILE) {
    $files = [System.Windows.Forms.Clipboard]::GetFileDropList()
    if ($files.Count -gt 0) {
        $src  = $files[0]
        $ext  = [System.IO.Path]::GetExtension($src).TrimStart('.')
        if (-not $ext) { $ext = "bin" }
        $FILENAME   = "$TS-$Name.$ext"
        $LOCAL_FILE = Join-Path $TMP $FILENAME
        Copy-Item $src $LOCAL_FILE
    }
}

if (-not $LOCAL_FILE) {
    [System.Windows.Forms.MessageBox]::Show(
        "Toma screenshot (Win+Shift+S) o copia archivo en Explorer",
        "Upload: sin archivo",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit 1
}

# SCP al servidor
$REMOTE_PATH = "$REMOTE_DIR/$FILENAME"
& scp -q $LOCAL_FILE "${SERVER}:${REMOTE_PATH}"
if ($LASTEXITCODE -ne 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "No se pudo conectar a corhild",
        "Upload: error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    Remove-Item $LOCAL_FILE -ErrorAction SilentlyContinue
    exit 1
}

$CLAUDE_REF = "@$REMOTE_PATH"

# Limpiar clipboard (para que Ctrl+V no repita el path)
[System.Windows.Forms.Clipboard]::Clear()

# Limpiar archivo tmp
Remove-Item $LOCAL_FILE -ErrorAction SilentlyContinue

# Auto-tipear en VS Code (equivalente a osascript keystroke en Mac)
$wshell = New-Object -ComObject wscript.shell
Start-Sleep -Milliseconds 500
$wshell.AppActivate('Visual Studio Code')
Start-Sleep -Milliseconds 400

# Escapar caracteres especiales de SendKeys: + ^ % ~ ( ) { } [ ]
$escaped = $CLAUDE_REF -replace '([+^%~(){}[\]])', '{$1}'
$wshell.SendKeys($escaped)

# Notificación
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon   = [System.Drawing.SystemIcons]::Information
$notify.Visible = $true
$notify.ShowBalloonTip(3000, "Upload OK ✓ auto-pegado", $FILENAME, [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 3
$notify.Dispose()
