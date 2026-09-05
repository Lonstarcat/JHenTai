from __future__ import annotations

import sys

from PySide6.QtWidgets import QApplication

from app.core.logging_config import configure_logging
from app.core.paths import AppPaths
from app.services.database_service import DatabaseService
from app.services.credential_service import CredentialService
from app.services.settings_service import SettingsService
from app.ui.main_window import MainWindow
from app.ui.theme_manager import ThemeManager


def main() -> int:
    paths = AppPaths.create()
    paths.ensure_directories()
    configure_logging(paths.log_dir)

    database = DatabaseService(paths.database_path)
    database.initialize()
    settings_service = SettingsService(paths.settings_path)

    application = QApplication(sys.argv)
    application.setApplicationName("Manga Library Toolkit")
    application.setOrganizationName("MangaLibraryToolkit")
    theme_manager = ThemeManager(application, settings_service.load().theme_mode)
    credentials = CredentialService()
    window = MainWindow(
        database=database,
        settings_service=settings_service,
        credentials=credentials,
        theme_manager=theme_manager,
    )
    window.show()
    return application.exec()


if __name__ == "__main__":
    raise SystemExit(main())
