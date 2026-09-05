import unicodedata

from app.models.gallery_folder import UnicodeStatus
from app.services.unicode_service import detect_unicode_status, normalize_nfc


def test_detect_nfc_and_nfd() -> None:
    nfc = "シャモナベ"
    nfd = unicodedata.normalize("NFD", nfc)
    assert detect_unicode_status(nfc) == UnicodeStatus.NFC
    assert detect_unicode_status(nfd) == UnicodeStatus.NFD


def test_normalize_nfc() -> None:
    nfc = "ブルーアーカイブ"
    assert normalize_nfc(unicodedata.normalize("NFD", nfc)) == nfc
