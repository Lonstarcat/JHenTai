from __future__ import annotations

import unicodedata

from app.models.gallery_folder import UnicodeStatus


def detect_unicode_status(value: str) -> UnicodeStatus:
    """Classify text without mutating it; NFC wins when both forms are equal."""
    if value == unicodedata.normalize("NFC", value):
        return UnicodeStatus.NFC
    if value == unicodedata.normalize("NFD", value):
        return UnicodeStatus.NFD
    return UnicodeStatus.OTHER


def normalize_nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value)
