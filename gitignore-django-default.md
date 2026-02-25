# ==========================================
# PYTHON & DJANGO CORE
# ==========================================
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# Django Specifics
*.log
local_settings.py
db.sqlite3
db.sqlite3-journal
# Media: sube la carpeta pero no el contenido (imágenes de prueba)
media/*
!media/.gitkeep

# ==========================================
# SEGURIDAD Y VARIABLES DE ENTORNO (CRÍTICO)
# ==========================================
# Nunca subir claves de API o credenciales de DB
.env
.env.local
.env.*.local
secrets.json

# ==========================================
# IDE: GOOGLE ANTIGRAVITY / IDX / VS CODE
# ==========================================
.vscode/*
# Mantener config de equipo, ignorar estado local de usuario
!.vscode/settings.json
!.vscode/tasks.json
!.vscode/launch.json
!.vscode/extensions.json
*.code-workspace
.history/
.idx/

# ==========================================
# ESTRATEGIA DE AGENTE (PERSONALIDAD)
# ==========================================
# 1. Bloquear todo lo que genere el agente automáticamente (logs, memoria, caché)
.agent/

# 2. PERMITIR (Whitelist) explícitamente las reglas y flujos que creamos
# Esto asegura que tu "Socio Técnico" esté disponible para quien clone el repo
!.agent/rules/
!.agent/workflows/

# 3. Volver a ignorar basura que el IDE pueda crear DENTRO de las carpetas permitidas
.agent/rules/*.tmp
.agent/workflows/*.tmp
.agent/**/logs/
.agent/**/artifacts/

# ==========================================
# FRONTEND / SISTEMA
# ==========================================
node_modules/
npm-debug.log
yarn-error.log
.DS_Store
Thumbs.db
