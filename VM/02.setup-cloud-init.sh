#!/bin/bash
set -e # Detiene el script si ocurre algún error

# ==========================================
# Variables de Configuración
# ==========================================
VM_ID=9000
VM_NAME="ubuntu-2404-template"
IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG_NAME="noble-server-cloudimg-amd64.img"
ISO_PATH="/var/lib/vz/template/iso"
STORAGE="local-lvm"
DISK_SIZE="20G"
RAM_SIZE="4096"
CORES="2"

# ==========================================
# 1. Obtención y Actualización de Imagen
# ==========================================
echo "🔄 Verificando actualizaciones de la imagen Ubuntu 24.04..."
mkdir -p $ISO_PATH
cd $ISO_PATH
# El parámetro -N solo descarga si la versión del servidor es más reciente
wget -N $IMG_URL

# Opcional: Destruir la template anterior si necesitas regenerarla (Descomentar con precaución)
# echo "🗑️ Eliminando template anterior si existe..."
# qm destroy $VM_ID 2>/dev/null || true

# ==========================================
# 2. Construcción de la VM Base
# ==========================================
echo "⚙️ Creando VM base ($VM_ID)..."
qm create $VM_ID --name $VM_NAME --memory $RAM_SIZE --cores $CORES --net0 virtio,bridge=vmbr0

echo "💾 Importando disco a $STORAGE..."
qm importdisk $VM_ID $ISO_PATH/$IMG_NAME $STORAGE

echo "🔧 Configurando hardware y Cloud-Init..."
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0
qm set $VM_ID --ide2 $STORAGE:cloudinit
qm set $VM_ID --boot c --bootdisk scsi0
qm set $VM_ID --serial0 socket --vga serial0

echo "📈 Expandiendo disco a $DISK_SIZE..."
qm resize $VM_ID scsi0 $DISK_SIZE

# ==========================================
# 3. Sellado
# ==========================================
echo "🔒 Convirtiendo a Template..."
qm template $VM_ID

echo "✅ Template $VM_NAME ($VM_ID) generado correctamente."

# ==========================================
# 4. Limpieza
# ==========================================
echo "🗑️ Eliminando script de instalación..."
rm setup-cloud-init.sh
