#!/bin/bash
# ==============================================================================
# Hardening de Sistema: Creación de usuario y bloqueo de Root
# ==============================================================================

# 1. Crear el usuario soporte (Te pedirá que asignes una contraseña)
echo "👤 Creando usuario 'soporte'..."
adduser soporte

# 2. Añadir 'soporte' al grupo sudo (Administrador)
usermod -aG sudo soporte

# 3. Configurar llaves SSH para 'soporte' (Copiar las que ya tenía root)
echo "🔑 Migrando llaves SSH..."
mkdir -p /home/soporte/.ssh
cp /root/.ssh/authorized_keys /home/soporte/.ssh/ 2>/dev/null || echo "No hay llaves en root, recuerda añadir la tuya en /home/soporte/.ssh/authorized_keys"
chown -R soporte:soporte /home/soporte/.ssh
chmod 700 /home/soporte/.ssh
chmod 600 /home/soporte/.ssh/authorized_keys

# 4. Bloquear el login por SSH de root
echo "🛡️ Bloqueando acceso SSH directo a root..."
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# 5. Reiniciar servicio SSH para aplicar cambios
systemctl restart ssh

echo "✅ Listo. A partir de ahora, entra al servidor con: ssh soporte@tu-ip"
