from __future__ import annotations

from dataclasses import dataclass

import keyring
from keyring.errors import KeyringError, PasswordDeleteError


@dataclass(frozen=True, slots=True)
class CredentialState:
    ipb_member_id: bool
    ipb_pass_hash: bool
    igneous: bool


class CredentialStorageError(RuntimeError):
    pass


class CredentialService:
    """Store EH cookies in the OS credential vault, never in settings or logs."""

    SERVICE_NAME = "MangaLibraryToolkit.EHentai"
    COOKIE_NAMES = ("ipb_member_id", "ipb_pass_hash", "igneous")

    def set_cookie(self, name: str, value: str) -> None:
        self._validate_name(name)
        if value:
            try:
                keyring.set_password(self.SERVICE_NAME, name, value)
            except KeyringError as error:
                raise CredentialStorageError("无法写入 Windows Credential Manager") from error
        else:
            self.delete_cookie(name)

    def get_cookie(self, name: str) -> str | None:
        self._validate_name(name)
        try:
            return keyring.get_password(self.SERVICE_NAME, name)
        except KeyringError as error:
            raise CredentialStorageError("无法读取 Windows Credential Manager") from error

    def delete_cookie(self, name: str) -> None:
        self._validate_name(name)
        try:
            keyring.delete_password(self.SERVICE_NAME, name)
        except PasswordDeleteError:
            return
        except KeyringError as error:
            raise CredentialStorageError("无法更新 Windows Credential Manager") from error

    def get_cookies(self) -> dict[str, str]:
        result: dict[str, str] = {}
        for name in self.COOKIE_NAMES:
            value = self.get_cookie(name)
            if value:
                result[name] = value
        return result

    def state(self) -> CredentialState:
        cookies = self.get_cookies()
        return CredentialState(*(name in cookies for name in self.COOKIE_NAMES))

    @classmethod
    def _validate_name(cls, name: str) -> None:
        if name not in cls.COOKIE_NAMES:
            raise ValueError(f"Unsupported credential name: {name}")
