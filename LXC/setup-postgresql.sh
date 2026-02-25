#!/bin/bash

# ==============================================================================
# SETUP PARA LXC DE BASE DE DATOS (PRODUCCIÓN)
# Stack: Ubuntu 24.04 / Debian 12 + PostgreSQL (Latest)
# Función: Servidor de Base de Datos Dedicado
# Autor: Generado por Antigravity, basado en scripts de ctrbts (Fernando Merlo)
# Fecha: 2026-02-19
# Uso:
#     Crear el archivo con 
#         nano setup-postgresql.sh
#     Pegar el contenido de este archivo. Guardar (Ctrl+O, Ctrl+X) y ejecutar:
#         chmod +x setup-postgresql.sh
#         ./setup-postgresql.sh
# ==============================================================================

set -e # Detener si hay error crítico

# 0. VARIABLES DE CONFIGURACIÓN
NEW_USER="soporte"
TIMEZONE="America/Argentina/Buenos_Aires"
DB_NAME="mi_db_prod"
DB_USER="mi_usuario_db"
DB_PASSWORD="CAMBIAR_ESTA_PASSWORD"
DOCKER_SUBNET="192.168.1.100/32" # <-- Cambiado a la IP específica de tu LXC Docker por máxima seguridad

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Ejecuta este script como root.${NC}"
  exit 1
fi

echo -e "${GREEN}>>> Iniciando aprovisionamiento del servidor de DB...${NC}"

# 1. SISTEMA BASE
timedatectl set-timezone "$TIMEZONE"
apt update && apt full-upgrade -y
apt install -y curl ca-certificates gnupg ufw zsh mc git htop sudo

# 2. CREACIÓN DE USUARIO (Automatizado y unificado)
if id "$NEW_USER" &>/dev/null; then
    echo -e "${YELLOW}El usuario $NEW_USER ya existe.${NC}"
else
    echo -e "${YELLOW}>>> Creando usuario $NEW_USER...${NC}"
    # Crear usuario sin pedir contraseña interactivamente
    adduser --disabled-password --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    
    # Migrar llaves SSH de root de forma segura
    if [ -f "/root/.ssh/authorized_keys" ]; then
        mkdir -p /home/$NEW_USER/.ssh
        cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/
        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
        chmod 700 /home/$NEW_USER/.ssh
        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
        echo -e "${GREEN}Llaves SSH migradas con éxito.${NC}"
    else
        echo -e "${RED}ADVERTENCIA: No se encontraron llaves SSH en root. No bloquearemos el login por contraseña para evitar un lockout.${NC}"
    fi
fi

# 3. INSTALACIÓN DE POSTGRESQL
install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

apt update
apt install -y postgresql postgresql-contrib

PG_VERSION=$(ls /etc/postgresql/ | sort -V | tail -n 1)

# 4. CONFIGURACIÓN DE POSTGRESQL
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${YELLOW}La base de datos $DB_NAME ya existe.${NC}"
else
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';" || true
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
    sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO '$TIMEZONE';"
fi

PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

if ! grep -q "$DOCKER_SUBNET" "$PG_HBA"; then
    echo "host    $DB_NAME        $DB_USER        ${DOCKER_SUBNET}            scram-sha-256" >> "$PG_HBA"
fi

# 5. FIREWALL Y HARDENING SSH (Al final, para evitar cortes abruptos)
echo -e "${YELLOW}>>> Aplicando Firewall y Seguridad SSH...${NC}"

# Manejo seguro de UFW en LXC
ufw allow ssh || true
ufw allow from "$DOCKER_SUBNET" to any port 5432 || true
# Habilitamos UFW sin que aborte el script si el kernel LXC rechaza iptables
echo "y" | ufw enable || echo -e "${RED}Aviso: UFW no pudo iniciar (común en LXC Unprivileged). Gestiona el firewall desde el Datacenter de Proxmox.${NC}"

# Bloqueo de Root condicionado
if [ -f "/home/$NEW_USER/.ssh/authorized_keys" ]; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart ssh
fi

systemctl restart postgresql
systemctl enable postgresql

# 6. LIMPIEZA
apt autoremove -y
apt clean
rm setup-postgresql.sh

# 7. FINALIZACIÓN
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   SETUP DE DB FINALIZADO EXITOSAMENTE   ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "1. PostgreSQL $PG_VERSION activo en el puerto 5432."
echo -e "2. Usuario de sistema: $NEW_USER (con sudo y zsh)."
echo -e "3. Base de datos: $DB_NAME / Usuario DB: $DB_USER."
echo -e "4. Acceso externo habilitado SOLO para: $DOCKER_SUBNET."
echo -e "5. Firewall activo."
echo -e "\n${RED}IMPORTANTE:${NC} Verifica que $DOCKER_SUBNET coincida con tu red real."
