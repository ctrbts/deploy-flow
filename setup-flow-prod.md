### Instrucciones previas

Este script es la pieza clave para eliminar la fricción: convierte un contenedor LXC "vacío" (recién creado en Proxmox) en un servidor de producción listo, instalando dependencias, configurando PostgreSQL, Nginx, Gunicorn y permisos.

### El Script (`deploy/setup_server.sh`)

```bash
#!/bin/bash

# ==============================================================================
# Script de configuración inicial para LXC (Ubuntu 24.04)
# Autor: Fernando Merlo / ssh -L 5001:localhost:5001 tu_usuario@ip_de_la_vm
# ==============================================================================

# Detener el script si hay errores
set -e

# --- 1. VARIABLES DE CONFIGURACIÓN (EDITAR POR PROYECTO) ---
PROJECT_NAME="mi_proyecto"        # Nombre del proyecto (usado para carpetas y Nginx)
DB_NAME="mi_db_prod"              # Nombre de la base de datos PostgreSQL
DB_USER="mi_usuario_db"           # Usuario de PostgreSQL
DB_PASSWORD="mi_password_seguro"  # Contraseña para el usuario DB
PROJECT_DIR="/var/www/$PROJECT_NAME"

# Colores para logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> Iniciando configuración del servidor para: $PROJECT_NAME ${NC}"

# Verificar que se corre como root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Por favor, ejecuta este script como root.${NC}"
  exit 1
fi

# --- 2. ACTUALIZACIÓN DEL SISTEMA E INSTALACIÓN DE DEPENDENCIAS ---
echo -e "${YELLOW}>>> Actualizando sistema e instalando dependencias base...${NC}"
apt update && apt upgrade -y
apt install -y \
    python3-venv python3-dev python3-pip \
    libpq-dev postgresql postgresql-contrib \
    nginx curl git build-essential

# --- 3. CONFIGURACIÓN DE BASE DE DATOS (POSTGRESQL) ---
echo -e "${YELLOW}>>> Configurando PostgreSQL...${NC}"

# Verificar si la DB ya existe para no fallar
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${YELLOW}La base de datos $DB_NAME ya existe. Saltando creación.${NC}"
else
    echo -e "${GREEN}Creando usuario y base de datos...${NC}"
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" || true
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'America/Argentina/Buenos_Aires';"
fi

# --- 4. CONFIGURACIÓN DEL ENTORNO PYTHON ---
echo -e "${YELLOW}>>> Configurando entorno virtual Python...${NC}"

# Asegurar que estamos en el directorio correcto (asumiendo que clonaste o copiaste aquí)
# Si el script se ejecuta desde deploy/, subimos un nivel
cd "$(dirname "$0")/.." 
CURRENT_DIR=$(pwd)

# Crear venv si no existe
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}Entorno virtual creado.${NC}"
else
    echo -e "${YELLOW}El entorno virtual ya existe.${NC}"
fi

# Instalar requerimientos
echo -e "${YELLOW}>>> Instalando dependencias de requirements.txt...${NC}"
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt
./venv/bin/pip install gunicorn psycopg2-binary dj-database-url python-decouple

# --- 5. CONFIGURACIÓN DE VARIABLES DE ENTORNO (.ENV) ---
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}>>> Creando archivo .env de producción...${NC}"
    cat <<EOF > .env
DEBUG=False
SECRET_KEY=$(openssl rand -base64 32)
ALLOWED_HOSTS=localhost,127.0.0.1,tudominio.folp.unlp.edu.ar
DATABASE_URL=postgres://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME
EOF
    echo -e "${RED}IMPORTANTE: Se ha generado un archivo .env. REVISALO Y AJUSTA ALLOWED_HOSTS.${NC}"
fi

# --- 6. GESTIÓN DE ARCHIVOS ESTÁTICOS Y MIGRACIONES ---
echo -e "${YELLOW}>>> Ejecutando migraciones y collectstatic...${NC}"
./venv/bin/python manage.py migrate --noinput
./venv/bin/python manage.py collectstatic --noinput

# --- 7. CONFIGURACIÓN DE PERMISOS ---
echo -e "${YELLOW}>>> Ajustando permisos (www-data)...${NC}"
# Asignamos el grupo www-data al proyecto, pero mantenemos tu usuario como dueño si es necesario
# Para producción estricta en LXC, www-data suele ser dueño de media/static
chown -R www-data:www-data media staticfiles
chmod -R 775 media staticfiles
# Asegurar que la DB de sqlite (si quedó por error) no moleste, aunque usamos Postgres
rm -f db.sqlite3

# --- 8. CONFIGURACIÓN DE SYSTEMD (GUNICORN) ---
echo -e "${YELLOW}>>> Configurando Gunicorn y Systemd...${NC}"

# Copiar o enlazar archivos de servicio
# Usamos 'cp' en lugar de 'ln' para permitir editar en servidor sin romper git, 
# pero 'ln' es mejor para CI/CD. Usaremos enlaces simbólicos según tu workflow.

ln -sf "$CURRENT_DIR/deploy/gunicorn.socket" /etc/systemd/system/gunicorn.socket
ln -sf "$CURRENT_DIR/deploy/gunicorn.service" /etc/systemd/system/gunicorn.service

# Recargar systemd y habilitar sockets
systemctl daemon-reload
systemctl enable --now gunicorn.socket
# Reiniciar por si ya existía
systemctl restart gunicorn

# --- 9. CONFIGURACIÓN DE NGINX ---
echo -e "${YELLOW}>>> Configurando Nginx...${NC}"

ln -sf "$CURRENT_DIR/deploy/nginx.conf" /etc/nginx/sites-enabled/$PROJECT_NAME
# Borrar default si existe
rm -f /etc/nginx/sites-enabled/default

# Testear configuración
nginx -t

systemctl restart nginx

# --- 10. FINALIZACIÓN ---
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   DESPLIEGUE FINALIZADO EXITOSAMENTE   ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "1. Revisa el archivo .env si necesitas ajustar ALLOWED_HOSTS."
echo -e "2. Tu aplicación debería estar corriendo en el puerto 80 (Nginx) -> Socket -> Gunicorn."
echo -e "3. Verifica el estado con: systemctl status gunicorn"

```

---

### Cómo usar este script en un Proyecto Nuevo

El flujo para un despliegue desde cero en un LXC nuevo sería:

1. **En tu PC (Desarrollo):**

* Asegúrate de que `setup_server.sh` esté en la carpeta `deploy/` del repo.
* Edita las variables al inicio del script (`PROJECT_NAME`, `DB_NAME`, etc.) y haz commit.

1. **En el Servidor (LXC Proxmox):**

* Entra por SSH.
* Clona tu repositorio en `/var/www/` (o donde prefieras):

```bash
mkdir -p /var/www
cd /var/www
git clone https://github.com/tu-usuario/tu-proyecto.git
cd tu-proyecto

```

* Dale permisos de ejecución al script y córrelo:

```bash
chmod +x deploy/setup_server.sh
sudo ./deploy/setup_server.sh

```

1. **Resultado:**

* El script instalará todo.
* Creará la base de datos PostgreSQL.
* Configurará Nginx y Gunicorn.
* Tu sitio estará online.

### Detalles Técnicos Importantes

1. **Idempotencia:** El script verifica si la base de datos ya existe antes de intentar crearla. Esto significa que si lo corres dos veces, no romperá nada (aunque reiniciará los servicios).
2. **Ubicación Relativa:** El script usa `cd "$(dirname "$0")/.."` para ubicarse en la raíz del proyecto, sin importar desde dónde lo ejecutes, siempre que esté dentro de la carpeta `deploy`.
3. **Seguridad Básica:** Genera una `SECRET_KEY` aleatoria si crea el archivo `.env` por primera vez.
4. **Limpieza:** Asume que usarás PostgreSQL, por lo que borra `db.sqlite3` si existe para evitar confusiones (dado que Django podría intentar usarla si la configuración falla).
