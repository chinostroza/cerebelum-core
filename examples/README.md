# Cerebelum Core - Test Client

Script de prueba simple en Python para verificar que el servidor gRPC está funcionando correctamente.

## Requisitos

- Python 3.7+
- pip

## Instalación

### En tu servidor de producción:

```bash
# 1. Ir al directorio del proyecto
cd ~/cerebelum-core/examples

# 2. Crear y activar entorno virtual
python3 -m venv venv
source venv/bin/activate

# 3. Instalar las dependencias de Python
pip install grpcio grpcio-tools

# 4. Generar los archivos Python desde los archivos .proto
python -m grpc_tools.protoc \
  -I../priv/protos \
  --python_out=. \
  --grpc_python_out=. \
  --pyi_out=. \
  ../priv/protos/worker_service.proto
```

## Ejecución

```bash
# Asegúrate que el venv está activado
source venv/bin/activate

# Hacer el script ejecutable
chmod +x test_client.py

# Ejecutar el test
python test_client.py
```

Para salir del entorno virtual cuando termines:
```bash
deactivate
```

## Lo que hace el script

El script realiza las siguientes pruebas:

1. **Conexión**: Verifica conectividad con el servidor en localhost:9090
2. **Registro de Worker**: Registra un worker de prueba llamado "test-worker-python-1"
3. **Heartbeat**: Envía un heartbeat para verificar que el worker está vivo
4. **Blueprint**: Envía un workflow simple con 3 pasos (step1 → step2 → step3)
5. **Ejecución**: Intenta ejecutar el workflow
6. **Des-registro**: Limpia el worker registrado

## Salida esperada

```
============================================================
Cerebelum Core gRPC Test Client
============================================================

Connecting to: localhost:9090
✓ Connected successfully!

1. Testing Worker Registration...
   ✓ Registration successful!
   Message: Worker registered successfully
   Heartbeat interval: 10000ms

2. Testing Heartbeat...
   ✓ Heartbeat acknowledged: True

3. Testing Blueprint Submission...
   ✓ Blueprint submitted!
   Valid: True
   Workflow hash: abc123...

4. Testing Workflow Execution...
   ✓ Workflow execution started!
   Execution ID: exec_xyz789
   Status: running

5. Testing Worker Unregistration...
   ✓ Worker unregistered successfully!

============================================================
Test Summary
============================================================
✓ PASS - Worker Registration
✓ PASS - Heartbeat
✓ PASS - Blueprint Submission
✓ PASS - Workflow Execution
✓ PASS - Worker Unregistration

Total: 5/5 tests passed

🎉 All tests passed!
```

## Troubleshooting

### Error: "Connection refused"

El servidor no está corriendo o no está escuchando en el puerto 9090:

```bash
# Verificar que el contenedor está corriendo
docker compose ps

# Ver logs del servidor
docker compose logs app

# Verificar que el puerto está abierto
sudo ss -tlnp | grep 9090
```

### Error: "Module not found: worker_service_pb2"

No generaste los archivos Python desde los .proto:

```bash
# Activar venv primero
source venv/bin/activate

# Generar los archivos
python -m grpc_tools.protoc \
  -I../priv/protos \
  --python_out=. \
  --grpc_python_out=. \
  --pyi_out=. \
  ../priv/protos/worker_service.proto
```

### Error: "No module named 'grpc'"

Instalar las dependencias dentro del venv:

```bash
# Activar venv primero
source venv/bin/activate

# Instalar dependencias
pip install grpcio grpcio-tools
```

## Uso desde otros lenguajes

Este mismo .proto puede ser usado para generar clientes en otros lenguajes:

### Kotlin/Java
```bash
protoc --java_out=. --grpc-java_out=. worker_service.proto
```

### TypeScript/Node.js
```bash
npm install @grpc/grpc-js @grpc/proto-loader
protoc --js_out=import_style=commonjs:. --grpc_out=. worker_service.proto
```

### Go
```bash
protoc --go_out=. --go-grpc_out=. worker_service.proto
```
