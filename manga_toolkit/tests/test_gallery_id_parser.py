from app.models.gallery_folder import GalleryType
from app.services.gallery_id_parser import parse_gallery_id, strip_gallery_prefix


def test_parse_normal_gallery_id() -> None:
    result = parse_gallery_id("2185199 - [天気輪 (甘露アメ)] 标题")
    assert result is not None
    assert result.gallery_type == GalleryType.NORMAL
    assert result.gallery_id == "2185199"


def test_parse_archive_gallery_id() -> None:
    result = parse_gallery_id("Archive - 3107629 - [玉ぼん] 标题")
    assert result is not None
    assert result.gallery_type == GalleryType.ARCHIVE
    assert result.gallery_id == "3107629"


def test_ignore_non_gallery_name() -> None:
    assert parse_gallery_id("thumb") is None
    assert parse_gallery_id("notes") is None


def test_strip_gallery_prefix() -> None:
    assert strip_gallery_prefix("Archive - 3107629 - 标题") == "标题"
    assert strip_gallery_prefix("2185199 - 标题") == "标题"
