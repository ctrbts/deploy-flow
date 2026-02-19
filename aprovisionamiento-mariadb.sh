#!/bin/bash
# ==============================================================================
# Aprovisionamiento de MariaDB LXC (Stateful)
# OS Soportado: Debian 12 / Ubuntu 24.04
# ==============================================================================
set -e # Detiene el script si ocurre un error

### VARIABLES DE ENTORNO (¡Modificar antes de ejecutar!) ###
DOCKER_SUBNET="10.0.0.0/24" # Subred donde vive tu Docker VM
DB_ROOT_PASSWORD="CambiarPorUnPasswordSeguro123!"
############################################################

echo "🚀 Iniciando aprovisionamiento de MariaDB..."

# 1. Seteamos el timezone
timedatectl set-timezone America/Argentina/Buenos_Aires

# 2. Actualización y dependencias
apt-get update && apt-get upgrade -y
apt-get install -y mariadb-server ufw

# 3. Configuración de Firewall (Restringir acceso al motor)
echo "🛡️ Configurando UFW para aislar la base de datos..."
ufw allow ssh
ufw allow from $DOCKER_SUBNET to any port 3306
ufw --force enable

# 4. Asegurar MariaDB (Equivalente a mysql_secure_installation)
echo "🔐 Aplicando políticas de seguridad en MariaDB..."
mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -u root -p"${DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# 5. Exponer MariaDB a la red privada
echo "⚙️ Configurando Bind Address..."
sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf

systemctl restart mariadb
systemctl enable mariadb

echo "✅ MariaDB listo para producción. Puerto 3306 expuesto SOLO a $DOCKER_SUBNET."
