from __future__ import annotations

from app.services.credential_service import CredentialService


def test_legacy_cookie_is_migrated_to_emangato_service(monkeypatch) -> None:
    saved: list[tuple[str, str, str]] = []

    def get_password(service: str, name: str) -> str | None:
        if service == CredentialService.LEGACY_SERVICE_NAME and name == "igneous":
            return "legacy-cookie"
        return None

    monkeypatch.setattr("keyring.get_password", get_password)
    monkeypatch.setattr("keyring.set_password", lambda service, name, value: saved.append((service, name, value)))
    assert CredentialService().get_cookie("igneous") == "legacy-cookie"
    assert saved == [(CredentialService.SERVICE_NAME, "igneous", "legacy-cookie")]
