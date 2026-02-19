#!/bin/bash

# Asegurar que el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (ej. sudo ./deploy.sh)"
  exit 1
fi

echo "========================================="
echo "   Automatización Gunicorn + Nginx       "
echo "========================================="

# 1. Verificar requerimientos
echo "-> Verificando dependencias instaladas..."
for req in python3 nginx systemctl ss; do
    if ! command -v $req &> /dev/null; then
        echo "❌ Error: '$req' no está instalado. Por favor instálalo y vuelve a intentar."
        exit 1
    fi
done
echo "✅ Dependencias básicas encontradas."

# 2. Recopilar datos de la aplicación
echo ""
read -p "Nombre del servicio (ej. mi_aplicacion): " SERVICE_NAME
read -p "Ruta absoluta de tu proyecto (ej. /var/www/mi_proyecto): " APP_DIR
read -p "Ruta del entorno virtual (deja en blanco si no usas, ej. /var/www/mi_proyecto/venv): " VENV_DIR
read -p "Módulo de entrada WSGI (ej. para Django: core.wsgi:application, para Flask: wsgi:app): " WSGI_MODULE
read -p "Usuario de Linux propietario de la app (ej. ubuntu, root, www-data): " APP_USER

# 3. Buscar la ruta de Gunicorn
if [ -n "$VENV_DIR" ]; then
    GUNICORN_CMD="$VENV_DIR/bin/gunicorn"
else
    GUNICORN_CMD=$(command -v gunicorn)
fi

if [ ! -f "$GUNICORN_CMD" ]; then
    echo "❌ No se encontró gunicorn. Asegúrate de tenerlo instalado (pip install gunicorn)."
    exit 1
fi
echo "✅ Gunicorn encontrado en: $GUNICORN_CMD"

# 4. Configurar IP/Dominio y verificar el puerto Nginx
echo ""
read -p "Ingresa tu IP o Dominio (ej. 192.168.1.10 o midominio.com): " SERVER_NAME

while true; do
    read -p "Elige el puerto de salida para Nginx (ej. 80, 8080): " NGINX_PORT
    # Verificar si el puerto ya está en uso
    if ss -tuln | grep -q ":$NGINX_PORT "; then
        echo "⚠️  El puerto $NGINX_PORT está ocupado. Por favor, intenta con otro."
    else
        echo "✅ Puerto $NGINX_PORT disponible."
        break
    fi
done

# 5. Crear el archivo de servicio Systemd
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SOCKET_FILE="${APP_DIR}/${SERVICE_NAME}.sock"

echo "-> Creando archivo de servicio en $SERVICE_FILE..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Gunicorn daemon for $SERVICE_NAME
After=network.target

[Service]
User=$APP_USER
Group=www-data
WorkingDirectory=$APP_DIR
# Usamos un socket Unix para mayor eficiencia entre Gunicorn y Nginx
ExecStart=$GUNICORN_CMD --access-logfile - --workers 3 --bind unix:$SOCKET_FILE $WSGI_MODULE

[Install]
WantedBy=multi-user.target
EOF

# 6. Crear el bloque de Nginx (Proxy Inverso)
NGINX_CONF="/etc/nginx/sites-available/$SERVICE_NAME"

echo "-> Configurando proxy inverso en Nginx..."
cat <<EOF > "$NGINX_CONF"
server {
    listen $NGINX_PORT;
    server_name $SERVER_NAME;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:$SOCKET_FILE;
    }
}
EOF

# Enlazar a sites-enabled
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

# Verificar si Nginx tiene errores de sintaxis
nginx -t
if [ $? -ne 0 ]; then
    echo "❌ Nginx detectó un error en la configuración. Revisa las rutas o el puerto."
    exit 1
fi

# 7. Iniciar y habilitar los servicios automáticamente
echo "-> Iniciando y habilitando servicios..."
systemctl daemon-reload
systemctl start "$SERVICE_NAME"
systemctl enable "$SERVICE_NAME"
systemctl restart nginx

echo "========================================="
echo "✅ ¡Despliegue finalizado con éxito!"
echo "Tu aplicación ya debería estar escuchando en: http://$SERVER_NAME:$NGINX_PORT"
echo "Puedes ver los logs de tu app con: sudo journalctl -u $SERVICE_NAME -f"
echo "========================================="
