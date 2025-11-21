# Cerebelum Examples

Esta carpeta contiene ejemplos de uso de Cerebelum en diferentes lenguajes.

## 📁 Estructura

```
examples/
├── python-sdk/          ⭐ Python DSL v1.2 (RECOMENDADO)
└── cerebelum-native-elixir/  Ejemplos en Elixir
```

---

## 🐍 Python SDK (Recomendado)

**Ubicación:** [`python-sdk/`](./python-sdk/)

El Python SDK incluye el nuevo **DSL v1.2** con todas las mejoras:

✅ Auto-wrapping (sin boilerplate manual)
✅ Excepciones nativas
✅ Sintaxis paralela explícita `[step_a, step_b]`
✅ Validación temprana de dependencias

### Quick Start

```bash
cd python-sdk
python3 example_quickstart.py
```

### Ejemplos Disponibles

1. **example_quickstart.py** - Tu primer workflow (< 1 min)
2. **example_complete_dsl.py** - E-commerce completo con paralelismo
3. **example_improved_dx.py** - Ver mejoras del DSL
4. **example_parallel_syntax.py** - Patrones de paralelismo avanzados

📖 **Documentación completa:** [python-sdk/README.md](./python-sdk/README.md)

---

## 🧪 Elixir Examples

**Ubicación:** [`cerebelum-native-elixir/`](./cerebelum-native-elixir/)

Ejemplos de integración con Cerebelum usando Elixir nativo.

---

## 🚀 Empezar Aquí

**Primera vez con Cerebelum?**

1. Ve a [`python-sdk/`](./python-sdk/)
2. Lee el [README.md](./python-sdk/README.md)
3. Ejecuta `python3 example_quickstart.py`
4. ¡Listo! 🎉

---

**Última actualización:** 2025-11-20
**Versión SDK:** v1.2.0
