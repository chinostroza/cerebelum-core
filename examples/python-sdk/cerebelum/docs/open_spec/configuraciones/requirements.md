# Requirements Document - Tab Bar Navigation y Configuración de Usuario

## Introduction

Este documento define los requerimientos para la implementación de un sistema de navegación mediante tab bar inferior en Toteat Mobile, que reemplaza el menú lateral actual. Esta mejora busca optimizar la experiencia de usuario, reducir pasos de navegación y proporcionar acceso rápido a funcionalidades esenciales según el rol del usuario (garzón, administrador, dueño).

### Purpose
Proporcionar una navegación intuitiva y eficiente mediante un tab bar fijo inferior que permita acceso rápido a las mesas del usuario, todas las mesas del restaurante, y opciones de perfil y configuración.

### Scope
- Tab bar inferior fija con tres navegaciones principales
- Vista "Mis Mesas" filtrada por usuario logueado
- Vista "Todas las Mesas" con sistema de filtros por sectores/zonas
- Modal "Ver Más" con opciones de perfil, cambio de usuario y configuración
- Gestión de perfil de usuario (visualización)
- Cambio de usuario con redirección a login
- Configuración del POS con permisos según rol
- Estados visuales para indicar sección activa

### Value Proposition
Una interfaz de navegación moderna y eficiente que reduce la fricción en las tareas diarias del personal de restaurante, proporcionando acceso inmediato a las funciones más utilizadas y configuraciones contextuales según el rol del usuario.

---

## Requirements

### Requirement 1: Tab Bar Navigation - Estructura y Visibilidad

**User Story:** Como usuario de Toteat Mobile (garzón o administrador), quiero ver un menú inferior fijo con tres opciones principales para navegar rápidamente entre las secciones más importantes de la aplicación.

#### Acceptance Criteria

1. WHEN la aplicación carga THEN el sistema SHALL mostrar una tab bar fija en la parte inferior con tres botones: "Mis Mesas", "Todas las Mesas" y "Ver Más"

2. WHILE el usuario está en la pantalla de inicio THEN la tab bar SHALL permanecer visible y fija en la parte inferior independientemente de la posición del scroll

3. WHEN el usuario toca cualquier botón de la tab THEN el sistema SHALL resaltar la tab activa usando color de acento para indicar la sección actual

4. WHERE el usuario navega a una pantalla de detalle (ej. detalle de mesa, detalle de orden) THEN la tab bar SHALL ocultarse para maximizar el espacio de pantalla

5. IF el usuario regresa al inicio desde una pantalla de detalle THEN la tab bar SHALL reaparecer con la tab previamente seleccionada aún resaltada

6. WHEN la tab bar se muestra THEN cada botón SHALL mostrar un ícono y etiqueta identificando claramente su función

7. WHILE la aplicación está en orientación vertical u horizontal THEN la tab bar SHALL mantener comportamiento y visibilidad consistentes en todos los tamaños de pantalla

8. WHERE el ancho de pantalla del dispositivo es menor a 375px THEN el sistema SHALL ajustar el espaciado de los botones para mantener usabilidad sin truncamiento de texto

### Requirement 2: Default Navigation - Todas las Mesas

**User Story:** Como usuario que inicia sesión en Toteat Mobile, quiero que la aplicación abra por defecto en "Todas las Mesas" para tener una visión general del restaurante inmediatamente.

#### Acceptance Criteria

1. WHEN un usuario inicia sesión exitosamente THEN el sistema SHALL navegar a la vista "Todas las Mesas" por defecto

2. IF la aplicación se reabre desde estado de segundo plano THEN el sistema SHALL mantener la última tab vista a menos que la sesión haya expirado

3. WHEN "Todas las Mesas" carga como predeterminada THEN la tab bar SHALL resaltar el botón "Todas las Mesas" como activo

4. WHERE un usuario tiene mesas activas abiertas THEN el sistema SHALL seguir mostrando "Todas las Mesas" como predeterminada pero mostrar indicadores de badge para las mesas activas

5. IF el usuario selecciona manualmente una tab diferente THEN el sistema SHALL recordar esta selección para la sesión actual

6. WHEN el usuario cierra sesión y vuelve a iniciar sesión THEN el sistema SHALL resetear a "Todas las Mesas" como predeterminada independientemente de la sesión anterior

### Requirement 3: Mis Mesas - Vista Filtrada por Usuario

**User Story:** Como garzón, quiero ver únicamente las mesas que yo he abierto para concentrarme en mis propios clientes sin distracciones de otras mesas.

#### Acceptance Criteria

1. WHEN el usuario toca el botón "Mis Mesas" THEN el sistema SHALL mostrar únicamente las mesas que fueron abiertas por el usuario actualmente logueado

2. IF el usuario no tiene mesas abiertas THEN el sistema SHALL mostrar mensaje de estado vacío "No tienes mesas abiertas" con ilustración

3. WHILE se visualiza "Mis Mesas" THEN el sistema SHALL mostrar el estado de la mesa, tiempo transcurrido y resumen de órdenes para cada mesa

4. WHERE una mesa fue abierta por el usuario actual THEN SHALL aparecer en "Mis Mesas" independientemente del sector o zona a la que pertenezca

5. WHEN otro usuario abre una mesa THEN NO SHALL aparecer en la vista "Mis Mesas" del usuario actual

6. IF una mesa es cerrada o transferida a otro usuario THEN el sistema SHALL removerla de la vista "Mis Mesas" inmediatamente

7. WHILE se selecciona una mesa desde "Mis Mesas" THEN el sistema SHALL navegar a la vista de detalle de mesa manteniendo el contexto

8. WHERE el usuario tiene múltiples mesas abiertas THEN el sistema SHALL ordenarlas por actividad más reciente (última orden o modificación)

9. WHEN una nueva mesa es abierta por el usuario THEN el sistema SHALL agregarla a la vista "Mis Mesas" en tiempo real sin requerir actualización

### Requirement 4: Todas las Mesas - Vista General con Filtros

**User Story:** Como usuario con cualquier rol, quiero ver todas las mesas disponibles del restaurante y poder filtrarlas por sectores o zonas para encontrar mesas específicas rápidamente.

#### Acceptance Criteria

1. WHEN el usuario toca el botón "Todas las Mesas" THEN el sistema SHALL mostrar todas las mesas del restaurante independientemente de quién las abrió

2. IF las mesas están organizadas por sectores o zonas THEN el sistema SHALL mostrar un filtro de carrusel horizontal en la parte superior de la vista

3. WHILE se visualiza "Todas las Mesas" THEN el carrusel SHALL mostrar todos los sectores/zonas disponibles (ej. "Salón", "Bar", "Terraza", "Vip")

4. WHERE un filtro de sector es seleccionado THEN el sistema SHALL mostrar únicamente las mesas pertenecientes a ese sector

5. WHEN el usuario toca un chip de sector en el carrusel THEN el sistema SHALL resaltar el sector seleccionado y filtrar las mesas en consecuencia

6. IF "Todos" o el filtro predeterminado está seleccionado THEN el sistema SHALL mostrar todas las mesas sin filtrado por sector

7. WHILE las mesas están cargando THEN el sistema SHALL mostrar estados de carga tipo skeleton para indicar que los datos se están obteniendo

8. WHERE una mesa muestra diferentes indicadores de estado THEN el sistema SHALL usar señales visuales: disponible (gris/blanco), ocupada con badge de tiempo, reservada

9. WHEN una mesa es abierta o cerrada por cualquier usuario THEN el sistema SHALL actualizar el estado de la mesa en tiempo real para todos los usuarios viendo "Todas las Mesas"

10. IF el usuario toca una tarjeta de mesa THEN el sistema SHALL navegar a la vista de detalle de mesa con información completa y acciones disponibles

11. WHILE se hace scroll a través de muchas mesas THEN el sistema SHALL implementar renderizado eficiente de listas para mantener el rendimiento (lista virtualizada)

### Requirement 5: Ver Más - Modal de Opciones

**User Story:** Como usuario, quiero acceder a un menú de opciones personales y de configuración desde el tab "Ver Más" para gestionar mi perfil y ajustes de la aplicación.

#### Acceptance Criteria

1. WHEN el usuario toca el botón "Ver Más" THEN el sistema SHALL mostrar un modal bottom sheet con tres opciones: "Mi Perfil", "Cambiar de usuario", "Configuración"

2. IF el modal se abre THEN el sistema SHALL atenuar el fondo y permitir descartar tocando afuera o deslizando hacia abajo

3. WHILE el modal "Ver Más" está mostrado THEN cada opción SHALL mostrar un ícono y etiqueta descriptiva

4. WHERE el usuario está en la tab "Ver Más" THEN el botón de la tab SHALL mostrar estado activo con color de acento

5. WHEN el usuario selecciona cualquier opción del modal THEN el sistema SHALL navegar a la pantalla correspondiente y cerrar el modal

6. IF el usuario toca fuera del modal o el botón de retroceso THEN el sistema SHALL cerrar el modal y regresar a la tab activa previamente

7. WHILE el modal está animándose abierto o cerrado THEN el sistema SHALL usar transiciones suaves (duración 300ms con curva ease-out)

### Requirement 6: Mi Perfil - Visualización de Información de Usuario

**User Story:** Como usuario, quiero ver mi información de perfil (nombre, rol, horarios de turno) para verificar mi identidad y datos de sesión actual.

#### Acceptance Criteria

1. WHEN el usuario selecciona "Mi Perfil" THEN el sistema SHALL mostrar información del usuario incluyendo: nombre de usuario, rol, correo electrónico

2. IF el usuario tiene un turno activo THEN el sistema SHALL mostrar los timestamps de "Inicio turno" y "Término turno"

3. WHILE se visualiza el perfil THEN todos los campos SHALL ser de solo lectura sin capacidad de edición

4. WHERE el usuario tiene una foto de perfil THEN el sistema SHALL mostrarla; de lo contrario mostrar ícono de avatar predeterminado

5. WHEN la pantalla de perfil carga THEN el sistema SHALL obtener datos frescos del usuario desde el servidor para asegurar precisión

6. IF los datos del usuario fallan al cargar THEN el sistema SHALL mostrar mensaje de error "No se pudo cargar la información del perfil" con opción de reintentar

7. WHILE se visualiza el perfil THEN el sistema SHALL mostrar un botón "Volver" para regresar a la pantalla anterior

8. WHERE el usuario toca "Volver" THEN el sistema SHALL navegar de vuelta al inicio y restaurar la tab activa previamente

### Requirement 7: Cambiar de Usuario - Redirección a Login

**User Story:** Como usuario, quiero poder cerrar mi sesión y cambiar de usuario fácilmente para permitir que otro empleado use la aplicación en el mismo dispositivo.

#### Acceptance Criteria

1. WHEN el usuario selecciona "Cambiar de usuario" THEN el sistema SHALL limpiar inmediatamente el token de sesión actual

2. IF la sesión es limpiada THEN el sistema SHALL navegar a la pantalla de login independientemente del tipo de terminal (personal o compartida)

3. WHILE se navega al login THEN el sistema SHALL limpiar todos los datos de usuario en caché incluyendo perfil, mesas abiertas y preferencias

4. WHERE el dispositivo está configurado como "terminal compartida" THEN el sistema SHALL comportarse idénticamente a "terminal personal" para el cambio de usuario

5. WHEN la pantalla de login aparece THEN el sistema SHALL mostrar campos de usuario/contraseña vacíos listos para entrada de nuevo usuario

6. IF el usuario navega hacia atrás desde la pantalla de login THEN el sistema SHALL prevenir regresar a pantallas autenticadas sin credenciales válidas

7. WHILE se limpia la sesión THEN el sistema SHALL preservar las configuraciones a nivel de dispositivo (ajustes de impresora, ID de terminal) para el siguiente usuario

### Requirement 8: Configuración - Vista por Rol de Usuario (Garzón)

**User Story:** Como garzón, quiero ver la configuración del POS donde trabajo para conocer los ajustes del terminal, pero sin capacidad de modificarlos.

#### Acceptance Criteria

1. WHEN un usuario con rol "garzón" selecciona "Configuración" THEN el sistema SHALL mostrar la pantalla de configuración en modo solo lectura

2. IF el usuario es garzón THEN el sistema SHALL mostrar: Impresora, Nombre del Terminal, Gateway de Pago como campos no editables (las credenciales SHALL estar enmascaradas)

3. WHILE se visualiza la configuración como garzón THEN todos los campos SHALL aparecer como texto plano sin capacidad de edición

4. WHERE los valores de configuración se muestran THEN el sistema SHALL mostrar valores actuales obtenidos desde los ajustes del dispositivo o backend

5. WHEN la pantalla carga THEN el sistema SHALL incluir indicador visual (ícono de candado o etiqueta) mostrando "Solo lectura" o "Información del POS"

6. IF los datos de configuración fallan al cargar THEN el sistema SHALL mostrar mensaje de error "No se pudo cargar la configuración" con opción de reintentar

7. WHILE se visualiza la configuración THEN el sistema SHALL mostrar un botón "Volver" para regresar a la pantalla anterior

8. WHERE las credenciales del terminal de pago se muestran THEN el sistema SHALL enmascarar datos sensibles mostrando "••••••••" en lugar de los valores reales

### Requirement 9: Configuración - Vista Editable (Administrador/Dueño)

**User Story:** Como administrador o dueño, quiero poder editar la configuración del POS (impresora y terminal de pago) para ajustar los dispositivos según las necesidades del restaurante.

#### Acceptance Criteria

1. WHEN un usuario con rol "administrador" o "dueño" selecciona "Configuración" THEN el sistema SHALL mostrar pantalla de configuración con secciones editables: "Impresora" y "Terminal de Pago"

2. IF el usuario tiene privilegios de administrador THEN el sistema SHALL mostrar dropdown para "Impresora" y sección expandible para configuración de "Terminal de Pago"

3. WHERE el usuario selecciona "Impresora" THEN el sistema SHALL mostrar dropdown con dispositivos de impresora emparejados o impresoras de red configuradas para el restaurante

4. IF cualquier dropdown se abre THEN el sistema SHALL mostrar opciones claramente con la selección actual resaltada

5. WHILE cualquier campo tiene cambios sin guardar THEN el sistema SHALL habilitar un botón "Guardar" o "Aplicar cambios" en la parte inferior

6. WHERE el usuario toca "Guardar" THEN el sistema SHALL validar todas las selecciones y persistir los cambios al almacenamiento del dispositivo y/o backend

7. WHEN el guardado es exitoso THEN el sistema SHALL mostrar mensaje de confirmación "Configuración guardada exitosamente"

8. IF el guardado falla debido a error de red o validación THEN el sistema SHALL mostrar mensaje de error "No se pudo guardar la configuración" con opción de reintentar

9. WHILE el usuario toca "Volver" sin guardar THEN el sistema SHALL preguntar "¿Descartar cambios?" con opciones "Cancelar" y "Descartar"

10. WHERE los cambios son guardados THEN el sistema SHALL aplicar los nuevos ajustes inmediatamente para operaciones subsecuentes (impresión, pagos)

### Requirement 10: Configuración de Terminal de Pago - Campos Dinámicos por Proveedor

**User Story:** Como administrador o dueño que configura un terminal de pago, quiero ingresar los datos específicos requeridos por cada proveedor (GETNET, Mercado Pago, u otros) para que el sistema pueda levantar correctamente las intenciones de pago.

#### Acceptance Criteria

1. WHEN el usuario está en la pantalla de configuración con privilegios de administrador THEN el sistema SHALL mostrar sección "Terminal de Pago" con los siguientes campos: "Nombre del Terminal", "Gateway/Pasarela de Pago", y campos de credenciales dinámicos

2. IF el usuario ingresa "Nombre del Terminal" THEN el sistema SHALL aceptar entrada de texto alfanumérico hasta 50 caracteres para identificación personalizada (ej. "Terminal de garzón Joaquín López")

3. WHILE el usuario selecciona "Gateway/Pasarela de Pago" THEN el sistema SHALL proveer dropdown con proveedores de pago disponibles: "Mercado Pago", "GETNET", y "Otro"

4. WHERE "Mercado Pago" es seleccionado como gateway THEN el sistema SHALL mostrar un campo de entrada de texto etiquetado "ID de Terminal (Access Token)" aceptando formato de string alfanumérico

5. WHEN "GETNET" es seleccionado como gateway THEN el sistema SHALL mostrar un campo de entrada numérico etiquetado "ID de Terminal (Número Correlativo)" aceptando solo valores enteros

6. WHERE "Otro" es seleccionado como gateway THEN el sistema SHALL mostrar campos de texto genéricos: "Identificador 1", "Identificador 2" permitiendo cualquier entrada de string

7. WHEN la selección de gateway cambia THEN el sistema SHALL limpiar los campos de credenciales previos y mostrar solo los campos relevantes al proveedor recién seleccionado

8. IF el usuario intenta guardar sin llenar campos requeridos THEN el sistema SHALL resaltar en rojo los campos vacíos requeridos y mostrar mensaje de error "Complete todos los campos obligatorios"

9. WHILE se validan credenciales de Mercado Pago THEN el sistema SHALL verificar que el formato del Access Token coincida con el patrón "APP_USR-" seguido de caracteres alfanuméricos

10. WHERE se ingresa el ID de Terminal GETNET THEN el sistema SHALL validar que sea un entero positivo y no exceda 999999

11. WHEN las credenciales se guardan exitosamente THEN el sistema SHALL encriptar datos sensibles (API keys, tokens) antes de almacenar en el almacenamiento local del dispositivo y/o backend

12. IF el usuario visualiza la configuración como "garzón" THEN el sistema SHALL mostrar el nombre del terminal y tipo de gateway pero enmascarar/ocultar valores de credenciales (mostrar como "••••••••")

13. WHILE se inicia una intención de pago THEN el sistema SHALL usar el tipo de gateway configurado y credenciales para conectar con la API del proveedor de pago apropiado

14. WHERE las credenciales de pago son inválidas o expiradas THEN el sistema SHALL mostrar error "Error de autenticación con pasarela de pago" y solicitar al administrador actualizar la configuración

15. WHEN existen múltiples terminales en el restaurante THEN el sistema SHALL permitir que cada dispositivo tenga nombre de terminal único y credenciales almacenadas localmente

16. IF la configuración del terminal es actualizada THEN el sistema SHALL registrar el cambio con timestamp y usuario que hizo la modificación para propósitos de auditoría

### Requirement 11: Visual States and Transitions

**User Story:** Como usuario, quiero recibir feedback visual inmediato cuando interactúo con la navegación para entender claramente qué sección estoy viendo.

#### Acceptance Criteria

1. WHEN el usuario toca un botón de tab THEN el sistema SHALL cambiar la apariencia del botón inmediatamente (< 100ms) al estado activo

2. IF una tab está activa THEN el sistema SHALL usar color de acento (color primario) para ícono y etiqueta, y peso de fuente en negrita para la etiqueta

3. WHILE una tab está inactiva THEN el sistema SHALL usar color gris neutral para ícono y etiqueta con peso de fuente regular

4. WHERE el usuario cambia de tabs THEN el sistema SHALL animar la transición entre vistas usando animación de fundido o deslizamiento (duración 250ms)

5. WHEN un modal se abre o cierra THEN el sistema SHALL usar animación de deslizamiento arriba/abajo con fundido de fondo (duración 300ms)

6. IF el usuario realiza una acción (guardar, eliminar, etc.) THEN el sistema SHALL proporcionar feedback visual a través de cambios de estado de botón o indicadores de carga

7. WHILE el contenido está cargando THEN el sistema SHALL mostrar pantallas tipo skeleton o spinners de carga para indicar procesamiento

8. WHERE un botón es presionado THEN el sistema SHALL mostrar estado presionado con ligero cambio de escala u opacidad antes de activar la acción

---

## Non-Functional Requirements

### Performance
- WHEN el usuario cambia entre tabs THEN el sistema SHALL renderizar la nueva vista en menos de 300ms
- IF la lista de mesas contiene más de 50 elementos THEN el sistema SHALL usar renderizado virtualizado para mantener rendimiento de scroll a 60fps
- WHILE se cargan datos de mesas THEN el sistema SHALL implementar actualizaciones optimistas de UI para mostrar feedback inmediato

### Compatibility
- WHEN se accede desde dispositivos móviles THEN el sistema SHALL soportar iOS 13+ y Android 8+
- WHERE la app se ejecuta en tablets THEN el sistema SHALL adaptar el tamaño de la tab bar a pantallas más grandes apropiadamente
- IF el dispositivo tiene notch o indicador de inicio THEN el sistema SHALL aplicar safe area insets para prevenir superposición

### Accessibility
- WHEN un usuario navega usando lector de pantalla THEN todos los botones de tab SHALL tener etiquetas descriptivas (ej. "Mis Mesas, pestaña")
- IF se mide el contraste de color THEN todo el texto SHALL cumplir con estándares WCAG AA (ratio mínimo 4.5:1)
- WHILE se navega con teclado (teclado externo en tablet) THEN los botones de tab SHALL ser enfocables y activables con la tecla Enter

### Reliability
- WHEN la conexión de red se pierde THEN el sistema SHALL cachear los últimos datos vistos y mostrar indicador offline
- IF los datos fallan al cargar THEN el sistema SHALL proporcionar mensajes de error claros con acciones de reintento
- WHILE la sesión expira THEN el sistema SHALL redirigir graciosamente al login sin pérdida de datos

### Security
- WHEN se realizan cambios de configuración THEN el sistema SHALL verificar permisos de rol de usuario antes de permitir ediciones
- IF un usuario no autorizado intenta editar la configuración THEN el sistema SHALL denegar el acceso y registrar el intento
- WHILE se muestra información sensible THEN el sistema SHALL enmascarar u ocultar datos apropiadamente (ej. credenciales de proveedor de pago)
- WHERE las credenciales de pago se almacenan THEN el sistema SHALL encriptar datos sensibles (API keys, tokens, access tokens) usando encriptación AES-256
- WHEN se inician intenciones de pago THEN el sistema SHALL transmitir credenciales solo por HTTPS/TLS

---

## Technical Requirements

### Architecture and Design Principles

#### Clean Architecture

**Requirement:** La implementación SHALL seguir Clean Architecture con separación clara de capas y dependencias unidireccionales.

**Acceptance Criteria:**

1. WHEN se estructura el módulo THEN el sistema SHALL organizar el código en las siguientes capas:
   - **Domain Layer (dominio)**: Entidades, casos de uso, interfaces de repositorio
   - **Data Layer (datos)**: Implementaciones de repositorio, data sources, modelos de datos
   - **Presentation Layer (presentación)**: ViewModels, Estados de UI, eventos

2. IF se define una dependencia entre capas THEN SHALL seguir la regla: Presentación → Domain ← Data

3. WHILE se implementan casos de uso THEN SHALL contener únicamente lógica de negocio sin referencias a frameworks o librerías de UI

4. WHERE se requiera acceso a datos THEN la capa de dominio SHALL definir interfaces (contratos) que la capa de datos implementa

5. WHEN se crean entidades de dominio THEN SHALL ser Plain Old Kotlin Objects (POKOs) sin anotaciones de framework

6. IF se requiere mapeo entre capas THEN el sistema SHALL implementar mappers explícitos (DTOs → Entities, Entities → UI Models)

#### SOLID Principles

**Requirement:** El código SHALL adherirse a los principios SOLID para mantener alta cohesión y bajo acoplamiento.

**Acceptance Criteria:**

1. **Single Responsibility Principle (SRP)**
   - WHEN se crea una clase THEN SHALL tener una única razón para cambiar
   - IF un caso de uso gestiona configuración de terminal THEN SHALL hacer solo eso, sin responsabilidades mezcladas

2. **Open/Closed Principle (OCP)**
   - WHEN se implementa soporte para gateways de pago THEN SHALL usar abstracción para permitir extensión sin modificar código existente
   - IF se agrega nuevo proveedor de pago THEN SHALL extender interfaz sin modificar implementaciones existentes

3. **Liskov Substitution Principle (LSP)**
   - WHERE se usan interfaces de repositorio THEN las implementaciones SHALL ser intercambiables sin alterar el comportamiento esperado

4. **Interface Segregation Principle (ISP)**
   - WHEN se definen interfaces THEN SHALL ser específicas y cohesivas, evitando interfaces "gordas"
   - IF un componente solo necesita leer configuración THEN SHALL depender de interfaz de lectura, no de una interfaz completa CRUD

5. **Dependency Inversion Principle (DIP)**
   - WHEN se inyectan dependencias THEN las clases de alto nivel SHALL depender de abstracciones, no de implementaciones concretas
   - IF un ViewModel necesita un repositorio THEN SHALL depender de la interfaz del repositorio, no de su implementación

### Module Structure (Kotlin Multiplatform)

**Requirement:** La funcionalidad de configuración SHALL implementarse como módulo independiente siguiendo la estructura modular del proyecto Toteat.

**Acceptance Criteria:**

1. WHEN se crea el módulo THEN SHALL nombrarse `feature_configuration` siguiendo la convención de nomenclatura del proyecto

2. IF el módulo se agrega al proyecto THEN SHALL incluirse en `settings.gradle.kts` con: `include(":feature_configuration")`

3. WHILE se estructura el módulo THEN SHALL contener los siguientes source sets de Kotlin Multiplatform:
   - `commonMain/`: Código compartido (lógica de negocio, dominio, data)
   - `androidMain/`: Implementaciones específicas de Android
   - `iosMain/`: Implementaciones específicas de iOS
   - `commonTest/`: Tests unitarios compartidos
   - `androidUnitTest/`: Tests específicos de Android

4. WHERE se define `build.gradle.kts` THEN SHALL configurar:
   ```kotlin
   kotlin {
       androidTarget()
       listOf(iosX64(), iosArm64(), iosSimulatorArm64())

       sourceSets {
           commonMain.dependencies {
               implementation(projects.coreStateApi)
               implementation(projects.coreNetwork)
               // otras dependencias core
           }
       }
   }
   ```

5. WHEN se organiza el código fuente THEN SHALL seguir estructura de paquetes:
   ```
   feature_configuration/
   ├── src/
   │   ├── commonMain/kotlin/com/toteat/feature/configuration/
   │   │   ├── domain/
   │   │   │   ├── model/          (Entidades: TerminalConfig, PaymentGateway)
   │   │   │   ├── repository/     (Interfaces de repositorio)
   │   │   │   └── usecase/        (GetConfigUseCase, SaveConfigUseCase, ValidateCredentialsUseCase)
   │   │   ├── data/
   │   │   │   ├── repository/     (Implementaciones de repositorio)
   │   │   │   ├── datasource/     (Local: SharedPreferences/UserDefaults, Remote: API)
   │   │   │   └── model/          (DTOs para red/persistencia)
   │   │   └── presentation/
   │   │       ├── viewmodel/      (ConfigurationViewModel, ProfileViewModel)
   │   │       ├── state/          (ConfigurationUiState, eventos)
   │   │       └── mapper/         (Mappers Domain → UI)
   │   ├── androidMain/kotlin/com/toteat/feature/configuration/
   │   │   └── data/datasource/    (Android-specific: EncryptedSharedPreferences)
   │   └── iosMain/kotlin/com/toteat/feature/configuration/
   │       └── data/datasource/    (iOS-specific: Keychain)
   ```

6. IF el módulo necesita dependencias externas THEN SHALL declararlas en `commonMain` cuando sean multiplataforma o en source sets específicos para código nativo

7. WHILE se integra con otros módulos THEN SHALL:
   - Depender de `core_state_api` para manejo de estado
   - Depender de `core_network` para llamadas API
   - Depender de `core_event_bus` para comunicación entre features si es necesario

8. WHERE se exponen componentes del módulo THEN SHALL usar interfaces públicas claras y mantener implementaciones internas como `internal`

### Dependency Injection

**Requirement:** El módulo SHALL usar inyección de dependencias para gestionar el ciclo de vida de objetos y facilitar testing.

**Acceptance Criteria:**

1. WHEN se configura DI THEN el sistema SHALL usar Koin (si es el framework usado en el proyecto) o similar compatible con KMP

2. IF se definen módulos de Koin THEN SHALL organizarse por capa:
   ```kotlin
   val configurationDomainModule = module {
       factory { GetConfigurationUseCase(get()) }
       factory { SaveConfigurationUseCase(get()) }
       factory { ValidatePaymentCredentialsUseCase(get()) }
   }

   val configurationDataModule = module {
       single<ConfigurationRepository> { ConfigurationRepositoryImpl(get(), get()) }
       single { ConfigurationLocalDataSource(get()) }
       single { ConfigurationRemoteDataSource(get()) }
   }

   val configurationPresentationModule = module {
       factory { ConfigurationViewModel(get(), get(), get()) }
   }
   ```

3. WHILE se inyectan dependencias en ViewModels THEN SHALL recibir interfaces, no implementaciones concretas

4. WHERE se requiera configuración específica de plataforma THEN SHALL usar `expect`/`actual` para resolver dependencias nativas

### Testing Strategy

**Requirement:** El módulo SHALL incluir tests automatizados en múltiples niveles para asegurar calidad y mantenibilidad.

**Acceptance Criteria:**

1. WHEN se escriben tests THEN SHALL cubrir al menos:
   - **Unit Tests**: Casos de uso, ViewModels, Mappers (>80% cobertura)
   - **Integration Tests**: Repositorios con data sources mockeados
   - **UI Tests**: Flujos críticos de configuración

2. IF se testean casos de uso THEN SHALL usar repositorios mockeados y verificar lógica de negocio aisladamente

3. WHILE se testean ViewModels THEN SHALL verificar transiciones de estado y manejo de eventos

4. WHERE se requiera mockear dependencias THEN SHALL usar MockK (Kotlin) o framework compatible con KMP

5. WHEN se escriben tests de validación THEN SHALL cubrir casos:
   - Validación de formato Access Token Mercado Pago
   - Validación de ID numérico GETNET
   - Validación de campos requeridos
   - Encriptación y desencriptación de credenciales

### Code Quality and Standards

**Requirement:** El código SHALL cumplir con estándares de calidad y estilo definidos en el proyecto.

**Acceptance Criteria:**

1. WHEN se escribe código THEN SHALL pasar análisis estático con Detekt sin errores críticos

2. IF se definen funciones THEN SHALL tener complejidad ciclomática < 10

3. WHILE se escriben clases THEN SHALL seguir convenciones de nombres:
   - UseCases: `VerbNounUseCase` (ej. `GetConfigurationUseCase`)
   - Repositories: `NounRepository` (ej. `ConfigurationRepository`)
   - ViewModels: `NounViewModel` (ej. `ConfigurationViewModel`)

4. WHERE se documenta código THEN SHALL usar KDoc para clases públicas y funciones complejas

5. WHEN se hace commit THEN SHALL incluir mensaje descriptivo siguiendo Conventional Commits: `feat(config):`, `fix(config):`, `refactor(config):`

### Performance Considerations

**Requirement:** El módulo SHALL implementarse considerando rendimiento y eficiencia de recursos.

**Acceptance Criteria:**

1. WHEN se encriptan credenciales THEN el proceso SHALL completarse en < 100ms

2. IF se cargan configuraciones al inicio THEN SHALL usar carga asíncrona sin bloquear UI thread

3. WHILE se guardan datos THEN SHALL usar corutinas de Kotlin para operaciones I/O

4. WHERE se almacenan credenciales THEN SHALL preferir almacenamiento local cifrado sobre llamadas de red repetidas

5. WHEN se validan campos THEN SHALL implementar debounce (300ms) para evitar validaciones excesivas durante tipeo

---

## Assumptions and Dependencies

### Business and User Assumptions

1. Users have Android or iOS devices with touch screen capability
2. Backend API provides endpoints for user profile, table data, and configuration settings
3. Real-time updates are delivered via WebSocket or polling mechanism for table status changes
4. Printer and payment terminal configurations are stored in device local storage or backend configuration service
5. Authentication tokens are managed securely and validated on each API request
6. Design system includes defined color palette, typography, and spacing tokens
7. Role-based access control (RBAC) is implemented in backend and consistently enforced
8. Payment gateway integrations are available for:
   - **Mercado Pago**: REST API with Access Token authentication
   - **GETNET**: REST API with numeric terminal ID
9. Device has secure local storage capability for encrypted credential storage
10. Payment provider APIs support payment intent creation and status polling
11. Network connectivity is available for real-time payment processing (fallback to offline mode not supported for payments)
12. Each physical terminal device can be uniquely identified and configured independently

### Technical Dependencies

13. **Kotlin Multiplatform**: Proyecto base usa KMP 1.9.x o superior
14. **Gradle Version Catalog**: Dependencias gestionadas centralmente
15. **Compose Multiplatform**: UI layer usa Compose para Android e iOS
16. **Koin**: Framework de inyección de dependencias compatible con KMP
17. **Ktor**: Cliente HTTP para operaciones de red (si usado en `core_network`)
18. **Kotlinx.serialization**: Serialización/deserialización JSON
19. **Kotlinx.coroutines**: Manejo de concurrencia y asincronía
20. **SQLDelight o Room**: Persistencia local (si requerido para cache)
21. **EncryptedSharedPreferences (Android)**: Almacenamiento seguro en Android
22. **Keychain (iOS)**: Almacenamiento seguro en iOS
23. **MockK**: Framework de mocking para tests unitarios
24. **Turbine**: Testing de Flows de Kotlin
25. **Detekt**: Análisis estático de código
26. El proyecto Toteat está ubicado en: `/Users/dev/Documents/toteat`
27. El módulo `feature_configuration` debe integrarse con módulos existentes:
    - `core_state_api`: Para manejo de estado compartido
    - `core_network`: Para llamadas HTTP
    - `core_event_bus`: Para eventos inter-módulo
    - `ui_components`: Para componentes reutilizables de UI

---

## Future Considerations

### Feature Enhancements

- Push notifications for table events when app is in background
- Dark mode support for tab bar and all screens
- Multi-language support (Spanish, English, Portuguese)
- Analytics tracking for tab navigation patterns
- Customizable tab bar order based on user preferences
- Badge indicators on tabs showing number of active tables or pending actions
- Haptic feedback on tab selection for enhanced tactile response
- Swipe gestures to switch between tabs
- Tab bar animation effects (spring, bounce) for delightful interactions

### Payment Gateway Extensions

- Support for additional payment providers (Stripe, PayPal, local providers)
- QR code payment integration (payment links)
- Split payment functionality across multiple terminals
- Payment retry mechanism with exponential backoff
- Offline payment queue with sync when network restored
- Terminal health monitoring and diagnostics
- Automatic credential validation on save
- Payment transaction history and audit logs per terminal
- Multi-currency support for international restaurants

### Technical Improvements

- **Modularización adicional**: Extraer lógica de payment gateway a módulo `core_payment_gateway` para reuso
- **Feature Flags**: Implementar sistema de feature toggles para habilitar/deshabilitar funcionalidades por ambiente
- **Backend-driven UI**: Configuración de campos de terminal desde backend para agregar proveedores sin actualizar app
- **Arquitectura hexagonal**: Migrar a puertos y adaptadores para mayor flexibilidad en integraciones
- **Event Sourcing**: Para auditoría completa de cambios de configuración con capacidad de replay
- **CQRS**: Separar comandos de escritura y queries de lectura para optimización
- **GraphQL**: Para queries eficientes de configuración con solo los campos necesarios
- **State Machine**: Implementar máquina de estados para flujo de configuración con validaciones
- **Snapshot testing**: Para componentes de UI y asegurar consistencia visual
- **Contract testing**: Para verificar compatibilidad con APIs de payment gateways
- **Observabilidad**: Integrar OpenTelemetry para tracing distribuido
- **CI/CD**: Pipeline automatizado con:
  - Compilación multiplataforma
  - Tests automatizados (unit, integration, UI)
  - Análisis de código (Detekt, KtLint)
  - Cobertura de código
  - Generación de artefactos (APK, IPA)
  - Deploy automático a ambientes de staging
