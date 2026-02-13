#!/bin/bash

# ==============================================================================
# SETUP INICIALPARA LXC
# Stack: Ubuntu 24.04 + Django + Gunicorn + Nginx + PostgreSQL
# Ejecutar como ROOT una sola vez al crear el LXC
# ==============================================================================

# 1. Definir nombre del usuario operador
NEW_USER="soporte"

# 2. Crear usuario y agregarlo al grupo sudo
adduser $NEW_USER
usermod -aG sudo $NEW_USER

# 3. Seteamos el timezone
timedatectl set-timezone America/Argentina/Buenos_Aires

# 4. Actualizamos el sistema
apt update && apt full-upgrade -y && apt autoremove -y && apt autoclean
apt install mc git

# 5. Preparar /var/www para que 'soporte' pueda escribir sin sudo
# Esto es clave para poder hacer git clone sin problemas
mkdir -p /var/www
chown -R $NEW_USER:www-data /var/www
chmod -R 775 /var/www

# 6. Configurar el "Bit Pegajoso" (SGID)
# Esto hace que cualquier archivo creado dentro de /var/www herede el grupo www-data
chmod g+s /var/www

# 7. (Opcional) Instalar ACLs para seguridad granular
#apt update && apt install -y acl
#setfacl -R -m u:$NEW_USER:rwx /var/www
#setfacl -R -d -m u:$NEW_USER:rwx /var/www

echo "✅ Usuario '$NEW_USER' creado y /var/www configurado."
echo "👉 Ahora sal de root e ingresa como: ssh $NEW_USER@$(hostname -I | awk '{print $1}')"
