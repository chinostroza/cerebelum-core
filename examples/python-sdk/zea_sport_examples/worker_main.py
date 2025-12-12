#!/usr/bin/env python3
"""
ZEA Sport Platform - Cerebelum Worker

Este worker ejecuta todos los workflows de la plataforma.
Debe correr como proceso separado (o múltiples procesos para paralelismo).

Uso:
    python -m app.workers.main

    # O con variables de entorno:
    CEREBELUM_CORE_URL=localhost:9090 \
    CEREBELUM_WORKER_ID=worker-1 \
    DATABASE_URL=postgresql://localhost:5432/zea_sport_db \
    python -m app.workers.main
"""

import asyncio
import logging
import os
import signal
import sys
from typing import Optional

# Cerebelum SDK
from cerebelum import Worker

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)


class ZEASportWorker:
    """
    Worker principal para ZEA Sport workflows.

    Este worker:
    1. Se conecta a Cerebelum Core
    2. Registra workflows disponibles
    3. Espera por tasks asignadas
    4. Ejecuta steps usando tu código existente (repositories, use cases)
    5. Maneja graceful shutdown
    """

    def __init__(
        self,
        core_url: str,
        worker_id: str,
        database_url: str
    ):
        self.core_url = core_url
        self.worker_id = worker_id
        self.database_url = database_url
        self.worker: Optional[Worker] = None
        self._shutdown = False

        logger.info(f"Initializing ZEA Sport Worker: {worker_id}")
        logger.info(f"Core URL: {core_url}")

    async def initialize_database(self):
        """
        Inicializa la conexión a tu base de datos PostgreSQL.

        IMPORTANTE: Reutiliza el mismo código de inicialización
        que usa tu aplicación FastAPI.
        """
        logger.info("Initializing database connection...")

        try:
            # Opción 1: Si usas SQLAlchemy
            # from app.database import init_db
            # await init_db(self.database_url)

            # Opción 2: Si usas asyncpg directamente
            # import asyncpg
            # self.db_pool = await asyncpg.create_pool(self.database_url)

            # Opción 3: Si usas tortoise-orm
            # from tortoise import Tortoise
            # await Tortoise.init(
            #     db_url=self.database_url,
            #     modules={'models': ['app.models']}
            # )

            logger.info("✅ Database connection initialized")

        except Exception as e:
            logger.error(f"❌ Failed to initialize database: {e}")
            raise

    async def import_workflows(self):
        """
        Importa todos los workflows para que estén disponibles.

        Esto asegura que cuando Core asigne un task, el worker
        tenga acceso a los step functions.
        """
        logger.info("Importing workflows...")

        try:
            # Importar todos tus workflows
            # Esto hace que las funciones de steps estén disponibles
            # en el namespace de Python

            # from app.workflows.athlete_onboarding import (
            #     build_athlete_onboarding_workflow
            # )
            # from app.workflows.booking_request import (
            #     build_booking_request_workflow
            # )
            # from app.workflows.session_completion import (
            #     build_session_completion_workflow
            # )
            # from app.workflows.payment_report import (
            #     build_payment_report_workflow
            # )

            logger.info("✅ Workflows imported successfully")

        except Exception as e:
            logger.error(f"❌ Failed to import workflows: {e}")
            raise

    async def setup_signal_handlers(self):
        """
        Configura handlers para graceful shutdown.
        """
        def signal_handler(signum, frame):
            logger.info(f"Received signal {signum}, shutting down gracefully...")
            self._shutdown = True

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

    async def run(self):
        """
        Método principal que corre el worker.
        """
        try:
            # 1. Setup signal handlers
            await self.setup_signal_handlers()

            # 2. Initialize database
            await self.initialize_database()

            # 3. Import workflows
            await self.import_workflows()

            # 4. Create Cerebelum worker
            logger.info("Starting Cerebelum worker...")
            self.worker = Worker(
                core_url=self.core_url,
                worker_id=self.worker_id
            )

            # 5. Run worker loop
            logger.info(f"🚀 Worker {self.worker_id} ready!")
            logger.info(f"   Connected to: {self.core_url}")
            logger.info(f"   Database: {self.database_url[:30]}...")
            logger.info(f"   Waiting for tasks...")

            # Worker.run() es un loop infinito que:
            # - Poll por tasks desde Core
            # - Ejecuta steps asignados
            # - Reporta resultados
            await self.worker.run()

        except KeyboardInterrupt:
            logger.info("Worker stopped by user (Ctrl+C)")

        except Exception as e:
            logger.error(f"❌ Worker error: {e}", exc_info=True)
            raise

        finally:
            await self.cleanup()

    async def cleanup(self):
        """
        Cleanup resources on shutdown.
        """
        logger.info("Cleaning up resources...")

        try:
            # Close database connections
            # if hasattr(self, 'db_pool'):
            #     await self.db_pool.close()

            # Close Cerebelum worker
            if self.worker:
                # Worker cleanup (si existe método close)
                pass

            logger.info("✅ Cleanup completed")

        except Exception as e:
            logger.error(f"Error during cleanup: {e}")


async def main():
    """
    Entry point del worker.
    """
    # Read configuration from environment
    core_url = os.getenv('CEREBELUM_CORE_URL', 'localhost:9090')
    worker_id = os.getenv('CEREBELUM_WORKER_ID', f'zea-sport-worker-{os.getpid()}')
    database_url = os.getenv('DATABASE_URL')

    # Validate configuration
    if not database_url:
        logger.error("❌ DATABASE_URL environment variable is required")
        sys.exit(1)

    # Display banner
    print("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║               ZEA Sport Platform - Cerebelum Worker              ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    # Create and run worker
    worker = ZEASportWorker(
        core_url=core_url,
        worker_id=worker_id,
        database_url=database_url
    )

    await worker.run()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Worker terminated")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
