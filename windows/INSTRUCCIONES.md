# Setup Windows — Corhild Dev

## 1. Instalar prerequisitos
- Git for Windows: https://git-scm.com/download/win
- VS Code: https://code.visualstudio.com
- Extension VS Code Remote SSH: abrir VS Code → Ctrl+Shift+X → buscar "Remote - SSH"

## 2. SSH Key
Abrir Git Bash y ejecutar:
```bash
ssh-keygen -t ed25519 -C "windows-pc"
# Presionar Enter 3 veces (acepta defaults)

# Copiar key al servidor:
cat ~/.ssh/id_ed25519.pub | ssh geison@5.78.204.244 "cat >> ~/.ssh/authorized_keys"
# Pedirá la contraseña del servidor (solo esta vez)
```

## 3. SSH Config
Copiar el archivo `ssh/config` a:
  C:\Users\TU_USUARIO\.ssh\config

## 4. VS Code settings
Copiar `vscode/settings.json` a:
  C:\Users\TU_USUARIO\AppData\Roaming\Code\User\settings.json

Copiar `vscode/keybindings.json` a:
  C:\Users\TU_USUARIO\AppData\Roaming\Code\User\keybindings.json

## 5. Workspaces
Copiar la carpeta `workspaces/` a donde quieras (ej. Documentos).
Doble click en cualquier .code-workspace para abrir VS Code conectado al server.

## 6. Verificar
Abrir Git Bash y probar:
```bash
ssh corhild
```
Debe entrar al server sin pedir contraseña.

## Instancias disponibles
| Workspace | Título | Acceso |
|---|---|---|
| corhild-local | normal | Projects completo + port forwarding |
| corhild-staging | verde | facturacion-cr staging |
| corhild-prod | rojo | facturacion-cr prod (readonly) |

## 7. Extensiones VS Code (instalar en Windows)
Ctrl+Shift+X → buscar e instalar:
- `ms-vscode-remote.remote-ssh` — conectar al servidor
- `ms-vscode.live-server` — preview HTML local

## 8. Preview HTML en servidor (via Remote SSH)
1. Abrir corhild-local.code-workspace
2. Navegar al archivo .html
3. Click derecho → "Show Preview" (o Ctrl+Shift+P → "Live Preview: Show Preview")

## 9. Preview app web (Laravel/Vite)
1. Abrir corhild-local.code-workspace (tiene port forwarding activo)
2. En terminal del servidor: `php artisan serve` o `npm run dev`
3. VS Code detecta el puerto → notificación → click → abre en navegador
4. O: panel "Ports" (abajo) → click en el globo del puerto

## 10. Upload clipboard → corhild (Ctrl+Shift+U)
1. Copiar `scripts/upload.ps1` a `C:\Users\TU_USUARIO\scripts\upload.ps1`
2. Copiar `vscode/tasks.json` a `AppData\Roaming\Code\User\tasks.json`
3. Copiar `vscode/keybindings.json` a `AppData\Roaming\Code\User\keybindings.json`

### Uso:
- Screenshot: Win+Shift+S → seleccionar área → Ctrl+Shift+U en VS Code
- Archivo: Ctrl+C en Explorer → Ctrl+Shift+U en VS Code
- Aparece notificación "Upload OK" → pegar con Ctrl+V en el terminal
