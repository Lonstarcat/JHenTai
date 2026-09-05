from __future__ import annotations

from PySide6.QtCore import QObject, Signal, Slot

from app.models.gallery_status import GallerySite
from app.services.credential_service import CredentialService
from app.services.credential_service import CredentialStorageError
from app.services.gallery_page_checker import GalleryPageStatusChecker


class LoginTestWorker(QObject):
    completed = Signal(bool, str)
    finished = Signal()

    def __init__(self, credentials: CredentialService, site: GallerySite) -> None:
        super().__init__()
        self._credentials = credentials
        self._site = site

    @Slot()
    def run(self) -> None:
        checker: GalleryPageStatusChecker | None = None
        try:
            checker = GalleryPageStatusChecker(cookies=self._credentials.get_cookies())
            success, message = checker.test_login(self._site)
            self.completed.emit(success, message)
        except CredentialStorageError as error:
            self.completed.emit(False, str(error))
        except Exception as error:  # Worker boundary: always release the QThread.
            self.completed.emit(False, f"登录测试失败：{error}")
        finally:
            if checker is not None:
                checker.close()
            self.finished.emit()
