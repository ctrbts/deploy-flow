#!/bin/bash

# ==============================================================================
# SETUP PARA LXC DE BASE DE DATOS (PRODUCCIÓN)
# Stack: Ubuntu 24.04 / Debian 12 + PostgreSQL (Latest)
# Función: Servidor de Base de Datos Dedicado (Sin aplicaciones web ni Nginx)
# Autor: Generado por Antigravity, basado en scripts de ctrbts (Fernando Merlo)
# ==============================================================================

# Detener el script si ocurre un error
set -e

# ==============================================================================
# 1. VARIABLES DE CONFIGURACIÓN (¡EDITAR ANTES DE EJECUTAR!)
# ==============================================================================

# Configuración del Sistema
NEW_USER="soporte"
TIMEZONE="America/Argentina/Buenos_Aires"

# Configuración de Base de Datos
DB_NAME="mi_db_prod"              # Nombre de la base de datos a crear
DB_USER="mi_usuario_db"           # Usuario dueño de la DB
DB_PASSWORD="CAMBIAR_ESTA_PASSWORD" # Contraseña segura para el usuario DB

# Configuración de Red y Seguridad
# Subred desde donde se permitirán conexiones (ej. donde corre tu App/Docker)
# IMPORTANTE: Ajustar a la subred real de tu infraestructura
DOCKER_SUBNET="10.0.0.0/24" 

# Colores para logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ==============================================================================
# 2. VERIFICACIONES INICIALES
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Por favor, ejecuta este script como root.${NC}"
  exit 1
fi

echo -e "${GREEN}>>> Iniciando aprovisionamiento del servidor de Base de Datos...${NC}"

# ==============================================================================
# 3. CONFIGURACIÓN DEL SISTEMA BASE
# ==============================================================================

echo -e "${YELLOW}>>> Configurando zona horaria...${NC}"
timedatectl set-timezone "$TIMEZONE"

echo -e "${YELLOW}>>> Actualizando sistema e instalando herramientas base...${NC}"
apt update && apt full-upgrade -y
# Instalamos dependencias básicas y útiles para administración
apt install -y curl ca-certificates gnupg ufw zsh mc git htop

# ==============================================================================
# 4. CREACIÓN DE USUARIO OPERADOR ('soporte')
# ==============================================================================

if id "$NEW_USER" &>/dev/null; then
    echo -e "${YELLOW}El usuario $NEW_USER ya existe.${NC}"
else
    echo -e "${YELLOW}>>> Creando usuario $NEW_USER...${NC}"
    adduser --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    echo -e "${GREEN}Usuario $NEW_USER creado y agregado a sudoers.${NC}"
    
    # Configuración básica de Zsh para el usuario (opcional pero recomendado)
    echo -e "${YELLOW}>>> Configurando Zsh para $NEW_USER...${NC}"
    chsh -s "$(which zsh)" "$NEW_USER"
    
    # Instalación automatizada de Oh My Zsh (sin interacción)
    # Se ejecuta como el usuario soporte
    sudo -u "$NEW_USER" sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended" || true
    
    # Plugins útiles
    ZSH_CUSTOM="/home/$NEW_USER/.oh-my-zsh/custom"
    sudo -u "$NEW_USER" git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
    sudo -u "$NEW_USER" git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || true
    
    # Activar plugins en .zshrc
    sudo -u "$NEW_USER" sed -i 's/^plugins=(git)$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "/home/$NEW_USER/.zshrc"
fi

# ==============================================================================
# 5. INSTALACIÓN DE POSTGRESQL (REPO OFICIAL)
# ==============================================================================

echo -e "${YELLOW}>>> Instalando PostgreSQL desde repositorio oficial...${NC}"

# Agregar repositorio de PostgreSQL
install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

apt update
apt install -y postgresql postgresql-contrib

# Detectar versión instalada
PG_VERSION=$(ls /etc/postgresql/ | sort -V | tail -n 1)
echo -e "${GREEN}PostgreSQL versión $PG_VERSION instalada.${NC}"

# ==============================================================================
# 6. CONFIGURACIÓN DE POSTGRESQL (DB Y USUARIOS)
# ==============================================================================

echo -e "${YELLOW}>>> Configurando Base de Datos y Usuarios...${NC}"

# Verificar si la DB ya existe
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${YELLOW}La base de datos $DB_NAME ya existe. Saltando creación.${NC}"
else
    echo -e "${GREEN}Creando usuario $DB_USER y base de datos $DB_NAME...${NC}"
    
    # Crear usuario
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" || true
    
    # Crear base de datos
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    
    # Ajustes recomendados para el rol
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO '$TIMEZONE';"
fi

# ==============================================================================
# 7. CONFIGURACIÓN DE RED (LISTEN Y HBA)
# ==============================================================================

echo -e "${YELLOW}>>> Configurando acceso de red a PostgreSQL...${NC}"

PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

# Escuchar en todas las interfaces (0.0.0.0)
# Se usa sed para reemplazar la línea comentada o existente
if grep -q "^#listen_addresses = 'localhost'" "$PG_CONF"; then
    sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
elif grep -q "^listen_addresses = 'localhost'" "$PG_CONF"; then
    sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
else
    # Si no encuentra el patrón estándar, lo agregamos al final si no existe ya
    if ! grep -q "listen_addresses = '*'" "$PG_CONF"; then
        echo "listen_addresses = '*'" >> "$PG_CONF"
    fi
fi

# Configurar pg_hba.conf para permitir acceso desde la subred Docker
if ! grep -q "$DOCKER_SUBNET" "$PG_HBA"; then
    echo -e "\n# Acceso desde Subred Docker/App" >> "$PG_HBA"
    echo "host    all             all             ${DOCKER_SUBNET}            scram-sha-256" >> "$PG_HBA"
    echo -e "${GREEN}Regla agregada a pg_hba.conf para $DOCKER_SUBNET${NC}"
else
    echo -e "${YELLOW}Regla para $DOCKER_SUBNET ya existe en pg_hba.conf${NC}"
fi

# ==============================================================================
# 8. CONFIGURACIÓN DE FIREWALL (UFW)
# ==============================================================================

echo -e "${YELLOW}>>> Configurando Firewall (UFW)...${NC}"

# Resetear reglas para asegurar estado limpio (opcional, aquí solo agregamos)
# ufw reset

# Permitir SSH (puerto 22)
ufw allow ssh

# Permitir PostgreSQL (5432) SOLO desde la subred autorizada
ufw allow from "$DOCKER_SUBNET" to any port 5432

# Habilitar firewall
echo "y" | ufw enable

# ==============================================================================
# 9. FINALIZACIÓN Y REINICIO DE SERVICIOS
# ==============================================================================

echo -e "${YELLOW}>>> Reiniciando servicio PostgreSQL...${NC}"
systemctl restart postgresql
systemctl enable postgresql

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   SETUP DE DB FINALIZADO EXITOSAMENTE   ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "1. PostgreSQL $PG_VERSION activo en el puerto 5432."
echo -e "2. Usuario de sistema: $NEW_USER (con sudo y zsh)."
echo -e "3. Base de datos: $DB_NAME / Usuario DB: $DB_USER."
echo -e "4. Acceso externo habilitado SOLO para: $DOCKER_SUBNET."
echo -e "5. Firewall activo."
echo -e "\n${RED}IMPORTANTE:${NC} Verifica que $DOCKER_SUBNET coincida con tu red real."
