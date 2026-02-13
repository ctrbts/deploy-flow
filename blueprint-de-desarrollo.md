
# Blueprint de Desarrollo y Despliegue Django en LXC (Radix Flow)

Este documento tiene como objetivo eliminar la fricción, automatizar lo repetitivo y asegurar que el paso de Desarrollo (SQLite) a Producción (PostgreSQL) sea robusto.

## 1. Estructura de Directorios Estandarizada

Tdos los proyectos futuros deben seguir esta estructura. Moveremos los archivos de configuración de servidor a una carpeta raíz llamada `deploy`.

```text
nombre-proyecto/
├── .github/
│   └── workflows/
│       └── production.yml    <-- Tu CI/CD
├── config/                   <-- Configuración del proyecto Django (settings, urls, wsgi)
│   ├── settings.py           <-- Configurado para leer variables de entorno
│   └── ...
├── deploy/                   <-- Archivos para el LXC (Infraestructura)
│   ├── gunicorn.service
│   ├── gunicorn.socket
│   ├── nginx.conf
│   └── setup_server.sh       <-- Script de "One-Click Setup" para el LXC
├── apps/                     <-- (Opcional) Carpeta para agrupar tus aplicaciones
│   ├── core/
│   └── usuarios/
├── static/
├── media/
├── templates/
├── .env.example              <-- Plantilla de variables (SIN SECRETOS)
├── .gitignore                <-- Estricto
├── requirements.txt
└── manage.py

```

---

## 2. Configuración del Entorno (The 12-Factor App)

Para manejar la dualidad SQLite/PostgreSQL sin tocar código, usaremos **`python-decouple`** (o `django-environ`).

**Acción:** Instalar `pip install python-decouple dj-database-url`.

### `config/settings.py` (Fragmento Crítico)

Este código detecta automáticamente si estás en Dev o Prod.

```python
from decouple import config
import dj_database_url
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Seguridad: Si no encuentra la variable, falla (bueno para prod) o usa default (bueno para dev)
SECRET_KEY = config('SECRET_KEY', default='django-insecure-key-dev-only')

# DEBUG: True por defecto, pero en el servidor .env dirá False
DEBUG = config('DEBUG', default=True, cast=bool)

ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='localhost,127.0.0.1').split(',')

# Configuración de Base de Datos Híbrida
# En local (sin .env o sin DATABASE_URL), usa SQLite.
# En Prod (LXC), el .env tendrá DATABASE_URL=postgres://user:pass@localhost:5432/db
DATABASES = {
    'default': config(
        'DATABASE_URL',
        default=f'sqlite:///{BASE_DIR / "db.sqlite3"}',
        cast=dj_database_url.parse
    )
}

# Configuración de estáticos (Vital para Nginx)
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'  # Donde Nginx buscará
STATICFILES_DIRS = [BASE_DIR / "static"]

```

---

## 4. Flujo de Trabajo (Workflow)

### Paso 1: Desarrollo Local (PC)

1. Crear entorno: `python3 -m venv venv && source venv/bin/activate`.
2. Instalar: `pip install -r requirements.txt`.
3. **No crear archivo .env** (o crear uno básico): Al no haber `.env` con credenciales de DB, `settings.py` usará SQLite automáticamente.
4. Desarrollar, crear migraciones y probar.
5. **Git:**

* Nunca comitear `db.sqlite3` ni `.env`.
* Tu `.gitignore` debe incluir:

```text
__pycache__/
*.py[cod]
venv/
.env
db.sqlite3
media/
staticfiles/

```

### Paso 2: Preparación del Servidor (LXC Proxmox)

*Solo se hace una vez por proyecto.*

1. Crear LXC Ubuntu 24.04.
2. Instalar base: `apt install python3-venv python3-dev libpq-dev postgresql nginx git curl`.
3. Crear usuario y BD en Postgres.
4. Clonar repo en `/var/www/mi-proyecto`.
5. Crear archivo `.env` en producción:

```bash
nano /var/www/mi-proyecto/.env

```

*Contenido:*

```ini
DEBUG=False
SECRET_KEY=kjsdhfksjdhf... (Generar una real)
ALLOWED_HOSTS=midominio.folp.unlp.edu.ar,192.168.x.x
DATABASE_URL=postgres://usuario_db:password_db@localhost:5432/nombre_db

```

1. Ejecutar el script de setup (ubicado en `deploy/setup_server.sh` que debes crear). Este script debe:

* Crear el venv en el servidor.
* Enlazar simbólicamente los archivos de `deploy/gunicorn...` a `/etc/systemd/system/`.
* Enlazar simbólicamente `deploy/nginx.conf` a `/etc/nginx/sites-enabled/`.

### Paso 3: Despliegue Continuo (GitHub Actions)

Este es el corazón del flujo "sin fricción". Cuando haces `git push origin main`, GitHub ordena al LXC que se actualice.

**Archivo: `.github/workflows/production.yml**`

```yaml
name: Deploy to LXC

on:
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.LXC_HOST }}        # IP pública o accesible del LXC
          username: ${{ secrets.LXC_USER }}    # Usuario linux (ej: root o usuario deploy)
          key: ${{ secrets.LXC_SSH_KEY }}      # Tu clave privada SSH
          port: ${{ secrets.LXC_PORT }}        # Puerto SSH (por defecto 22)
          script: |
            # Definir variables
            PROJECT_DIR="/var/www/mi-proyecto"
            VENV_DIR="$PROJECT_DIR/venv"
            
            # Detener el error si algo falla
            set -e
            
            echo "🚀 Iniciando despliegue en $PROJECT_DIR..."
            cd $PROJECT_DIR
            
            # 1. Actualizar Código
            git fetch --all
            git reset --hard origin/main
            
            # 2. Actualizar dependencias
            echo "📦 Instalando requerimientos..."
            $VENV_DIR/bin/pip install -r requirements.txt
            
            # 3. Migraciones (Postgres)
            echo "🗃️ Aplicando migraciones..."
            $VENV_DIR/bin/python manage.py migrate --noinput
            
            # 4. Archivos Estáticos
            echo "🎨 Recopilando estáticos..."
            $VENV_DIR/bin/python manage.py collectstatic --noinput
            
            # 5. Reiniciar servicios
            echo "🔄 Reiniciando Gunicorn..."
            systemctl restart gunicorn
            
            # Opcional: Recargar Nginx si cambiaste config
            # systemctl reload nginx 
            
            echo "✅ Despliegue exitoso."

```

---

## 5. Archivos de Infraestructura (`deploy/`)

Para que el script de arriba funcione y el sistema sea estable, necesitas estos archivos en tu repositorio.

### A. `deploy/gunicorn.socket`

No uses puerto TCP (8000) internamente, usa Sockets Unix. Son más rápidos y seguros.

```ini
[Unit]
Description=gunicorn socket

[Socket]
ListenStream=/run/gunicorn.sock

[Install]
WantedBy=sockets.target

```

### B. `deploy/gunicorn.service`

```ini
[Unit]
Description=gunicorn daemon
Requires=gunicorn.socket
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/mi-proyecto
# Ruta absoluta al gunicorn dentro del venv
ExecStart=/var/www/mi-proyecto/venv/bin/gunicorn \
          --access-logfile - \
          --workers 3 \
          --bind unix:/run/gunicorn.sock \
          config.wsgi:application

[Install]
WantedBy=multi-user.target

```

### C. `deploy/nginx.conf`

```nginx
server {
    listen 80;
    server_name midominio.folp.unlp.edu.ar;

    location = /favicon.ico { access_log off; log_not_found off; }
    
    # Servir estáticos directamente (sin pasar por Python)
    location /static/ {
        root /var/www/mi-proyecto/staticfiles; # Ojo: debe coincidir con STATIC_ROOT
    }

    location /media/ {
        root /var/www/mi-proyecto/media;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/gunicorn.sock;
    }
}

```

---

## 6. Lista de Verificación (Checklist) para un Nuevo Proyecto

Para empezar un proyecto nuevo siguiendo este estándar:

1. [ ] Clonar estructura base (o crear carpetas `deploy/` y `config/`).
2. [ ] Copiar `settings.py` estandarizado (con `decouple`).
3. [ ] Desarrollar en local con SQLite.
4. [ ] Crear repo en GitHub.
5. [ ] Configurar **Secrets** en GitHub (`LXC_HOST`, `LXC_USER`, `LXC_SSH_KEY`).
6. [ ] Crear LXC en Proxmox.
7. [ ] Copiar clave pública SSH de GitHub Actions al `authorized_keys` del LXC.
8. [ ] Clonar repo en LXC y crear `.env` con credenciales de PostgreSQL.
9. [ ] Ejecutar `deploy/setup_server.sh` (o enlaces simbólicos manuales la primera vez).
10. [ ] Hacer un cambio en local, `git push`, y ver la magia.

### Nota sobre el Rollback

El script `rollback.sh` que tenías en `prefo2` es útil. Recomiendo mantenerlo en la carpeta `deploy/` del servidor. Si un despliegue rompe producción, entras por SSH y ejecutas `./deploy/rollback.sh`, que básicamente haría un `git reset --hard HEAD@{1}` y reiniciaría servicios.
