# Cerebelum Core - Production Deployment Guide

Guía completa para deployar Cerebelum Core en un servidor VPS usando Docker.

## 📋 Requisitos Previos

### En el Servidor VPS

- Ubuntu 20.04 LTS o superior (o Debian)
- PostgreSQL 12+ instalado y configurado
- Docker y Docker Compose instalados
- Al menos 2GB RAM
- 20GB espacio en disco
- Acceso SSH con permisos sudo

### Herramientas Locales

- Git
- SSH client

---

## 🎯 Configuración Paso a Paso

### 1. Preparar PostgreSQL en el Servidor

Como ya tienes PostgreSQL instalado, solo necesitas crear la base de datos y usuario:

```bash
# Conectarse a PostgreSQL como superusuario
sudo -u postgres psql

# Crear usuario y base de datos
CREATE USER cerebelum WITH PASSWORD 'tu_password_seguro_aqui';
CREATE DATABASE cerebelum_prod OWNER cerebelum;

# Dar permisos necesarios
GRANT ALL PRIVILEGES ON DATABASE cerebelum_prod TO cerebelum;

# Salir
\q
```

**Importante:** Guarda el password que usaste, lo necesitarás para la configuración.

### 2. Instalar Docker y Docker Compose

Si no están instalados:

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar Docker
curl -fsSL https://get.docker.com | sudo bash

# Agregar tu usuario al grupo docker
sudo usermod -aG docker $USER

# Instalar Docker Compose
sudo apt install docker-compose-plugin -y

# Verificar instalación
docker --version
docker compose version
```

**Importante:** Cierra sesión y vuelve a entrar para que los cambios de grupo tengan efecto.

### 3. Clonar el Repositorio

```bash
# Navegar al directorio donde quieres el proyecto
cd /opt  # o cualquier otro directorio

# Clonar el repositorio
git clone https://github.com/tu-usuario/cerebelum-core.git
# O si usas SSH:
# git clone git@github.com:tu-usuario/cerebelum-core.git

cd cerebelum-core
```

### 4. Configurar Variables de Entorno

```bash
# Copiar el archivo de ejemplo
cp .env.example .env

# Editar el archivo .env
nano .env  # o vim, o tu editor preferido
```

Configuración para **PostgreSQL externo** (tu caso):

```bash
# Database Configuration
DATABASE_HOST=host.docker.internal  # Para PostgreSQL en el mismo servidor
# DATABASE_HOST=localhost  # Alternativa si host.docker.internal no funciona
# DATABASE_HOST=172.17.0.1  # Otra alternativa (IP del host desde Docker)
DATABASE_PORT=5432
DATABASE_USER=cerebelum
DATABASE_PASSWORD=tu_password_aqui
DATABASE_NAME=cerebelum_prod

# Application Secrets
SECRET_KEY_BASE=<generar_uno_nuevo>
PHX_HOST=tu-dominio.com  # o la IP de tu servidor
PORT=4001

# gRPC Configuration
ENABLE_GRPC_SERVER=true
GRPC_PORT=9090

# Erlang/OTP Release Configuration
RELEASE_NODE=cerebelum@127.0.0.1
RELEASE_COOKIE=<generar_cookie_seguro>

# Database Pool Size
POOL_SIZE=10
```

**Generar SECRET_KEY_BASE:**

```bash
# Método 1: Usar mix (requiere Elixir instalado localmente)
mix phx.gen.secret

# Método 2: Usar OpenSSL
openssl rand -base64 64
```

**Generar RELEASE_COOKIE:**

```bash
openssl rand -base64 32
```

### 5. Configurar Docker para Acceder a PostgreSQL del Host

Si PostgreSQL está en el mismo servidor pero fuera de Docker, asegúrate que PostgreSQL acepte conexiones desde Docker:

```bash
# Editar pg_hba.conf
sudo nano /etc/postgresql/14/main/pg_hba.conf  # Ajusta la versión si es diferente

# Agregar esta línea (permite conexiones desde Docker):
# host    cerebelum_prod    cerebelum    172.17.0.0/16    md5

# Editar postgresql.conf
sudo nano /etc/postgresql/14/main/postgresql.conf

# Asegurarse que listen_addresses incluya localhost:
# listen_addresses = 'localhost, 127.0.0.1'

# Reiniciar PostgreSQL
sudo systemctl restart postgresql
```

### 6. Hacer el Script de Deploy Ejecutable

```bash
chmod +x deploy.sh
```

### 7. Ejecutar el Deployment

```bash
./deploy.sh
```

El script hará:
1. Validar que existe el archivo `.env`
2. Parar contenedores existentes
3. Construir la imagen Docker
4. Levantar los servicios
5. Ejecutar migraciones de base de datos

### 8. Verificar que Todo Funciona

```bash
# Ver logs de la aplicación
docker compose logs -f app

# Verificar que el contenedor está corriendo
docker compose ps

# Probar conexión a la aplicación
docker compose exec app bin/cerebelum_core rpc "IO.puts('Cerebelum is running!')"

# Verificar que gRPC está escuchando
sudo netstat -tlnp | grep 9090
# O usando ss:
sudo ss -tlnp | grep 9090
```

---

## 🔧 Comandos Útiles

### Gestión de Contenedores

```bash
# Ver logs en tiempo real
docker compose logs -f app

# Ver logs de las últimas 100 líneas
docker compose logs --tail=100 app

# Reiniciar la aplicación
docker compose restart app

# Parar todo
docker compose down

# Parar y eliminar volúmenes
docker compose down -v

# Reconstruir y levantar
docker compose up -d --build
```

### Migraciones de Base de Datos

```bash
# Ejecutar migraciones
docker compose exec app bin/cerebelum_core eval "Cerebelum.Release.migrate()"

# Rollback de migración
docker compose exec app bin/cerebelum_core eval "Cerebelum.Release.rollback(Cerebelum.Repo, 20241118000000)"
```

### Ejecutar Comandos Elixir

```bash
# IEx remoto (consola interactiva)
docker compose exec app bin/cerebelum_core remote

# Ejecutar código Elixir
docker compose exec app bin/cerebelum_core rpc "Application.get_env(:cerebelum_core, :grpc_port)"
```

### Debugging

```bash
# Ver variables de entorno del contenedor
docker compose exec app env

# Inspeccionar el contenedor
docker compose exec app /bin/sh

# Ver uso de recursos
docker stats cerebelum_app
```

---

## 🔄 Actualización del Código

Cuando tengas cambios nuevos:

```bash
# 1. Pull de los cambios
git pull origin main

# 2. Ejecutar el script de deploy
./deploy.sh
```

O manualmente:

```bash
# Parar servicios
docker compose down

# Reconstruir imagen
docker compose build app

# Levantar servicios
docker compose up -d

# Ejecutar migraciones
docker compose exec app bin/cerebelum_core eval "Cerebelum.Release.migrate()"
```

---

## 🔒 Seguridad y Firewall

### Configurar UFW (Ubuntu Firewall)

**IMPORTANTE:** Los puertos 4001 y 9090 están configurados para escuchar **solo en localhost** (127.0.0.1). Esto significa que solo servicios en el mismo servidor pueden acceder a ellos. **NO abras estos puertos en el firewall** a menos que necesites acceso externo.

```bash
# Permitir SSH (NECESARIO)
sudo ufw allow 22/tcp

# NO es necesario abrir los puertos 9090 ni 4001
# porque están configurados para localhost only en docker-compose.yml
#
# Solo abre estos puertos si necesitas acceso externo:
# sudo ufw allow 9090/tcp  # gRPC - solo si necesitas acceso desde otros servidores
# sudo ufw allow 4001/tcp  # HTTP API - solo si necesitas acceso desde otros servidores

# Activar firewall
sudo ufw enable

# Ver status
sudo ufw status
```

**Ventajas de localhost-only:**
- Mayor seguridad: Los servicios no son accesibles desde internet
- Los servicios en el mismo servidor pueden acceder vía `localhost:9090` o `localhost:4001`
- Ideal cuando tus backends están en el mismo servidor

### Reverse Proxy con Nginx (Opcional)

Si quieres usar Nginx como reverse proxy:

```bash
sudo apt install nginx -y
```

Crear configuración:

```nginx
# /etc/nginx/sites-available/cerebelum
server {
    listen 80;
    server_name tu-dominio.com;

    # gRPC proxy (requiere HTTP/2)
    location / {
        grpc_pass grpc://localhost:9090;
    }
}
```

---

## 📊 Monitoreo

### Ver Métricas

```bash
# Recursos del contenedor
docker stats cerebelum_app

# Logs de PostgreSQL
sudo tail -f /var/log/postgresql/postgresql-14-main.log
```

### Healthchecks

El contenedor incluye un healthcheck automático. Verifica con:

```bash
docker inspect cerebelum_app | grep -A 10 Health
```

---

## 🆘 Troubleshooting

### Problema: No puede conectar a PostgreSQL

**Error:** `** (DBConnection.ConnectionError) connection not available`

**Solución:**

1. Verificar que PostgreSQL está corriendo:
   ```bash
   sudo systemctl status postgresql
   ```

2. Verificar que el usuario y base de datos existen:
   ```bash
   sudo -u postgres psql -c "\du"
   sudo -u postgres psql -c "\l"
   ```

3. Probar conexión desde el host:
   ```bash
   psql -h localhost -U cerebelum -d cerebelum_prod
   ```

4. Si `host.docker.internal` no funciona, usa `172.17.0.1` en DATABASE_HOST

### Problema: Puerto 9090 ya está en uso

**Solución:**

```bash
# Ver qué está usando el puerto
sudo lsof -i :9090

# Matar el proceso si es necesario
sudo kill -9 <PID>

# O cambiar el puerto en .env
GRPC_PORT=9091
```

### Problema: Migraciones fallan

**Error:** `** (Postgrex.Error) FATAL ... database "cerebelum_prod" does not exist`

**Solución:**

```bash
# Crear la base de datos manualmente
sudo -u postgres createdb -O cerebelum cerebelum_prod

# Reintentar migración
docker compose exec app bin/cerebelum_core eval "Cerebelum.Release.migrate()"
```

### Problema: Contenedor se reinicia constantemente

**Solución:**

```bash
# Ver logs para identificar el error
docker compose logs --tail=50 app

# Verificar configuración
docker compose exec app env | grep DATABASE
```

---

## 📝 Checklist de Deployment

- [ ] PostgreSQL configurado y accesible
- [ ] Docker y Docker Compose instalados
- [ ] Repositorio clonado
- [ ] Archivo `.env` configurado con valores correctos
- [ ] SECRET_KEY_BASE generado
- [ ] RELEASE_COOKIE generado
- [ ] Firewall configurado (UFW o iptables)
- [ ] Script `deploy.sh` ejecutado exitosamente
- [ ] Contenedor corriendo: `docker compose ps`
- [ ] Migraciones aplicadas
- [ ] gRPC escuchando en puerto 9090
- [ ] Logs sin errores: `docker compose logs app`

---

## 🚀 Próximos Pasos

1. Configurar backups automáticos de PostgreSQL
2. Implementar monitoreo (Prometheus + Grafana)
3. Configurar SSL/TLS para gRPC
4. Setup de CI/CD automático
5. Configurar log aggregation (ELK stack)

---

## 📞 Soporte

Si encuentras problemas:

1. Revisa los logs: `docker compose logs app`
2. Verifica la configuración: `docker compose config`
3. Consulta la documentación en `/cerebelum-core/guides/`
4. Abre un issue en GitHub

---

**Última actualización:** Noviembre 19, 2024
**Versión:** 1.0.0
