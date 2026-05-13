# dev-setup — Corhild Dev Environment

Configuración de VS Code, upload script y workspaces para Mac y Windows.

## Estructura

```
mac/
  upload.sh                    # Cmd+Shift+U → upload clipboard/archivo → servidor
  corhild-local.code-workspace
  corhild-staging.code-workspace
  corhild-prod.code-workspace

windows/
  INSTRUCCIONES.md             # Paso a paso para Windows
  ssh/config                   # SSH hosts (corhild, corhild-local, staging, prod)
  vscode/
    settings.json
    keybindings.json
    tasks.json
  scripts/upload.ps1           # Ctrl+Shift+U → upload clipboard/archivo → servidor
  workspaces/
    corhild-local.code-workspace
    corhild-staging.code-workspace
    corhild-prod.code-workspace
```

## Upload (Cmd+Shift+U / Ctrl+Shift+U)

Sube al servidor cualquier cosa del clipboard:
- Screenshot (Cmd+Shift+4 en Mac, Win+Shift+S en Windows)
- Archivo copiado desde Finder/Explorer (Cmd+C / Ctrl+C)
- PDF copiado desde Preview/navegador

Auto-tipea `@/home/geison/tmp/archivo` en VS Code terminal.
