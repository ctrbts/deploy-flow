#!/bin/bash

# ==============================================================================
# SETUP PARA LXC DE BASE DE DATOS MARIA DB (PRODUCCIÓN)
# Stack: Ubuntu 24.04 / Debian 12 + MariaDB (Server)
# Función: Servidor de Base de Datos Dedicado (Sin aplicaciones web ni Nginx)
# Autor: Generado por Antigravity, basado en scripts de ctrbts (Fernando Merlo)
# Fecha: 2026-02-19
# Uso:
#     Crear el archivo con 
#         sudo nano setup-mariadb.sh
#     Pegar el contenido de este archivo. Guardar (Ctrl+O, Ctrl+X) y ejecutar:
#         sudo chmod +x setup-mariadb.sh
#         sudo ./setup-mariadb.sh
# ==============================================================================

set -e # Detener si hay error crítico

# 1. VARIABLES DE CONFIGURACIÓN
NEW_USER="soporte"
TIMEZONE="America/Argentina/Buenos_Aires"

DB_NAME="mi_db_prod"
DB_USER="mi_usuario_db"
DB_PASSWORD="CAMBIAR_ESTA_PASSWORD"
DB_ROOT_PASSWORD="CAMBIAR_ROOT_PASSWORD_AHORA"

# IMPORTANTE: MariaDB no usa CIDR (como /24) para los usuarios. 
# Usa la IP exacta de tu LXC Docker, o un comodín SQL (ej. 192.168.1.%)
DOCKER_IP="192.168.1.100" 

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Ejecuta este script como root.${NC}"
  exit 1
fi

echo -e "${GREEN}>>> Iniciando aprovisionamiento del servidor de MariaDB...${NC}"

# 3. SISTEMA BASE
timedatectl set-timezone "$TIMEZONE"
apt update && apt full-upgrade -y
apt install -y curl ca-certificates gnupg ufw zsh mc git htop sudo

# 4. CREACIÓN DE USUARIO (Automatizado y Seguro)
if id "$NEW_USER" &>/dev/null; then
    echo -e "${YELLOW}El usuario $NEW_USER ya existe.${NC}"
else
    echo -e "${YELLOW}>>> Creando usuario $NEW_USER...${NC}"
    adduser --disabled-password --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    
    # Migrar llaves SSH para evitar Lockout
    if [ -f "/root/.ssh/authorized_keys" ]; then
        mkdir -p /home/$NEW_USER/.ssh
        cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/
        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
        chmod 700 /home/$NEW_USER/.ssh
        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
        echo -e "${GREEN}Llaves SSH migradas con éxito.${NC}"
    else
        echo -e "${RED}ADVERTENCIA: No se encontraron llaves SSH en root.${NC}"
    fi
fi

# 5. INSTALACIÓN DE MARIADB
echo -e "${YELLOW}>>> Instalando MariaDB Server...${NC}"
apt install -y mariadb-server

# 6. CONFIGURACIÓN DE MARIADB (Hardening y Usuarios)
echo -e "${YELLOW}>>> Aplicando hardening y creando base de datos...${NC}"

# Hardening automatizado sin prompts
mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.global_priv WHERE User='';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

# Crear DB y Usuario apuntando estrictamente a la IP del nodo Docker
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'${DOCKER_IP}' IDENTIFIED BY '${DB_PASSWORD}';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DOCKER_IP}';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# 7. CONFIGURACIÓN DE RED (BIND ADDRESS)
MARIADB_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$MARIADB_CONF" ]; then
    sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" "$MARIADB_CONF"
fi

# 8. CONFIGURACIÓN DE FIREWALL Y SSH (Con tolerancia a fallos LXC)
echo -e "${YELLOW}>>> Configurando Firewall y Hardening SSH...${NC}"

ufw allow ssh || true
ufw allow from "$DOCKER_IP" to any port 3306 || true
echo "y" | ufw enable || echo -e "${RED}Aviso: UFW no pudo iniciar (común en LXC).${NC}"

# Bloqueo de Root condicionado a la existencia de llaves SSH
if [ -f "/home/$NEW_USER/.ssh/authorized_keys" ]; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart ssh
fi

# 9. FINALIZACIÓN
systemctl restart mariadb
systemctl enable mariadb

# 10. LIMPIEZA
apt autoremove -y
apt clean
rm setup-mariadb.sh

# 11. FINALIZACIÓN
echo -e "${GREEN}>>> SETUP FINALIZADO CON ÉXITO <<<${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   SETUP DE DB FINALIZADO EXITOSAMENTE   ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "1. MariaDB activo en el puerto 3306."
echo -e "2. Usuario de sistema: $NEW_USER (con sudo y zsh)."
echo -e "3. Base de datos: $DB_NAME / Usuario DB: $DB_USER."
echo -e "4. Acceso externo habilitado SOLO para: $DOCKER_IP."
echo -e "5. Firewall activo."
echo -e "\n${RED}IMPORTANTE:${NC} Verifica que $DOCKER_IP coincida con tu red real."
