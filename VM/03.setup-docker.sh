#!/bin/bash
# ==============================================================================
# Aprovisionamiento de Docker VM + Dockge (Gestión de Stacks)
# OS Soportado: Ubuntu 24.04 LTS
# ==============================================================================
set -e # Detiene el script si ocurre un error

echo "🚀 Iniciando aprovisionamiento de Docker Engine y Dockge..."

# 1. Seteamos el timezone (Añadido sudo)
sudo timedatectl set-timezone America/Argentina/Buenos_Aires

# 2. Actualización del sistema base (Forzado a modo no interactivo)
echo "📦 Actualizando paquetes del sistema..."
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update
sudo -E apt-get upgrade -yq
sudo -E apt-get install -yq ca-certificates curl gnupg lsb-release ufw btop

# 3. Configuración de Firewall (UFW)
echo "🛡️ Configurando Firewall base..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# 4. Instalación de Docker y dependencias oficiales
echo "🐳 Instalando Docker Engine..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(awk -F= '/^ID=/{print $2}' /etc/os-release)/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(awk -F= '/^ID=/{print $2}' /etc/os-release) \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Añadir el usuario actual al grupo docker
sudo usermod -aG docker $USER

# 5. Optimización de Producción: Rotación de Logs
echo "⚙️ Configurando rotación de logs..."
cat <<EOF | sudo tee /etc/docker/daemon.json > /dev/null
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
sudo systemctl enable docker

# 6. Despliegue de Dockge
echo "🚢 Instalando y levantando Dockge..."
sudo mkdir -p /opt/stacks/dockge
cd /opt/stacks/dockge

# Generar el compose de Dockge al vuelo
cat <<EOF | sudo tee compose.yaml > /dev/null
services:
  dockge:
    image: louislam/dockge:1
    restart: unless-stopped
    ports:
      - "127.0.0.1:5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /opt/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
EOF

sudo docker compose up -d

# 7. Limpieza
echo "🗑️ Eliminando script de instalación..."
rm setup-docker.sh

echo "====================================================================="
echo "✅ Aprovisionamiento completado con éxito."
echo "⚠️  IMPORTANTE: Cierra esta sesión SSH y vuelve a entrar para aplicar"
echo "    los permisos del grupo Docker a tu usuario."
echo "🔐 Para acceder a Dockge, abre un túnel desde tu PC local:"
echo "    ssh -L 5001:localhost:5001 tu_usuario@ip_de_la_vm"
echo "    Luego ingresa en tu navegador a http://localhost:5001"
echo "====================================================================="