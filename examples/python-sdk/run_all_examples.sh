#!/bin/bash
# Run all tutorials to verify they work correctly

set -e  # Exit on error

echo "======================================================================"
echo "🎓 TESTING ALL TUTORIALS"
echo "======================================================================"
echo ""

# Function to run tutorial and check success
run_tutorial() {
    local tutorial=$1
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶️  Running: $tutorial"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if PYTHONPATH=. python3 "$tutorial"; then
        echo ""
        echo "✅ $tutorial - PASSED"
        echo ""
    else
        echo ""
        echo "❌ $tutorial - FAILED"
        echo ""
        exit 1
    fi
}

# Run all tutorials in order (LOCAL mode only)
run_tutorial "01_hello_world.py"
run_tutorial "02_dependencies.py"
run_tutorial "03_parallel_execution.py"
run_tutorial "04_error_handling.py"
run_tutorial "05_complete_example.py"
run_tutorial "07_enterprise_onboarding.py"

echo "======================================================================"
echo "✅ ALL LOCAL TUTORIALS PASSED!"
echo "======================================================================"
echo ""
echo "Summary:"
echo "  ✓ 01_hello_world.py - Hello World básico"
echo "  ✓ 02_dependencies.py - Dependencias entre steps"
echo "  ✓ 03_parallel_execution.py - Ejecución paralela"
echo "  ✓ 04_error_handling.py - Manejo de errores"
echo "  ✓ 05_complete_example.py - E-commerce completo"
echo "  ✓ 07_enterprise_onboarding.py - Onboarding empresarial complejo"
echo ""
echo "📋 Tutorial 06 (DISTRIBUTED) not tested - requires Core running:"
echo "   • 06_distributed_server.py - Requiere Core en Terminal 1"
echo "   • 06_execute_workflow.py - Requiere server en Terminal 2"
echo ""
echo "🎉 Todos los tutoriales locales funcionando correctamente!"
echo ""
echo "💡 PRÓXIMOS PASOS:"
echo "   • Lee CHANGELOG.md para ver todas las mejoras"
echo "   • Prueba Tutorial 06 (modo distribuido) manualmente"
echo "   • Construye tu propio workflow!"
echo ""
