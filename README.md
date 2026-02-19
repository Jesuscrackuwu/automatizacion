Cómo usarlo en tu servidor:
Crea el archivo: nano deploy.sh

Pega el código y guarda (Ctrl+O, Enter, Ctrl+X).

Dale permisos de ejecución: chmod +x deploy.sh

Ejecútalo como superusuario: sudo ./deploy.sh

Notas sobre su funcionamiento:
Sockets en lugar de puertos internos: El script configura Gunicorn para que escuche a través de un Unix Socket (.sock) ubicado en la carpeta de tu app en lugar de un puerto interno (como el clásico 8000). Esto es mucho más eficiente, seguro y evita que tengas conflictos de puertos internos al subir múltiples aplicaciones.

Manejo de rutas: Automáticamente inyecta las variables de entorno para que el archivo de servicio systemd quede perfectamente configurado con tu usuario, tu entorno virtual y tu módulo.
