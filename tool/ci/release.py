"""Release-only packaging for disposable CI runners; no credentials are logged."""
from __future__ import annotations

import base64
import binascii
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = "com.lonstarcat.jhentai"


def version(root: Path = ROOT) -> str:
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$",
                      (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if match is None:
        raise ValueError("Invalid pubspec version")
    return match[1] + "e"


def run(*args: str, cwd: Path = ROOT) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def output_dir() -> Path:
    result = ROOT / "build/ci-release"
    result.mkdir(parents=True, exist_ok=True)
    return result


def signing_payload(encoded: str, properties: str, key_path: Path) -> tuple[bytes, str]:
    if not encoded.strip() or not properties.strip():
        raise ValueError("Both Android signing Secrets are required")
    try:
        key = base64.b64decode("".join(encoded.split()), validate=True)
    except (ValueError, binascii.Error) as from_error:
        raise ValueError("ANDROID_KEYSTORE_BASE64 is not valid Base64") from from_error
    if len(key) < 64:
        raise ValueError("Decoded Android keystore is empty or too small")
    # Preserve Java-properties password escaping; only replace the filesystem path.
    lines = properties.lstrip("\ufeff").splitlines()
    for field in ("storePassword", "keyPassword", "keyAlias"):
        if not any(re.match(rf"^\s*{field}\s*[:=]\s*\S", line) for line in lines):
            raise ValueError(f"ANDROID_KEY_PROPERTIES is missing {field}")
    lines = [line for line in lines if not re.match(r"^\s*storeFile\s*[:=]", line)]
    lines.append(f"storeFile={key_path.as_posix()}")
    return key, "\n".join(lines) + "\n"


def signing_paths() -> tuple[Path, Path]:
    # Only named CI files are touched; never inspect a developer's local keystore.
    temp = Path(os.environ["RUNNER_TEMP"])
    return temp / "jhentai-upload-keystore.p12", ROOT / "android/key.properties"


def restore_signing() -> None:
    key_path, props_path = signing_paths()
    if key_path.exists() or props_path.exists():
        raise ValueError("Refusing to overwrite existing signing files")
    key, properties = signing_payload(os.environ.get("KEYSTORE_BASE64", ""),
                                     os.environ.get("KEY_PROPERTIES", ""), key_path)
    for target, data in ((key_path, key), (props_path, properties.encode("utf-8"))):
        with target.open("xb") as handle:
            target.chmod(0o600)
            handle.write(data)


def verify_plist(app: Path, minimum: str) -> dict:
    plist_path = app / ("Contents/Info.plist" if minimum == "LSMinimumSystemVersion" else "Info.plist")
    with plist_path.open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != IDENTITY:
        raise ValueError("Unexpected Apple package identity")
    if info.get("CFBundleShortVersionString") != version().split("+")[0]:
        raise ValueError("Unexpected Apple package version")
    if minimum not in info:
        raise ValueError("Apple minimum deployment version is missing")
    return info


def apple_config() -> None:
    macos = os.environ["APPLE_TARGET"] == "macOS"
    target = "MACOSX_DEPLOYMENT_TARGET = 12.0\nONLY_ACTIVE_ARCH = NO\n" if macos else "IPHONEOS_DEPLOYMENT_TARGET = 15.0\n"
    config = Path(os.environ["RUNNER_TEMP"]) / "jhentai-deployment.xcconfig"
    config.write_text(target, encoding="utf-8")
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as handle:
        handle.write(f"XCODE_XCCONFIG_FILE={config}\n")


def package_android() -> None:
    for abi, label in (("armeabi-v7a", "armeabi-v7a"), ("arm64-v8a", "arm64-v8a"), ("x86_64", "x64")):
        source = ROOT / f"build/app/outputs/flutter-apk/app-{abi}-release.apk"
        if not source.is_file() or source.stat().st_size == 0:
            raise ValueError(f"Missing release APK: {abi}")
        shutil.copy2(source, output_dir() / f"JHenTai-{version()}-{label}.apk")


def package_macos() -> None:
    app = ROOT / "build/macos/Build/Products/Release/jhentai.app"
    info = verify_plist(app, "LSMinimumSystemVersion")
    if info["LSMinimumSystemVersion"] != "12.0":
        raise ValueError("Expected macOS 12.0 minimum")
    for executable in (app / "Contents/MacOS" / info["CFBundleExecutable"],
                       app / "Contents/Frameworks/App.framework/Versions/A/App"):
        arches = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
        if not {"x86_64", "arm64"}.issubset(arches):
            raise ValueError("Expected universal macOS binary")
    # Refresh nested signatures before signing the bundle; no Apple key is used.
    frameworks = app / "Contents/Frameworks"
    for framework in sorted(frameworks.glob("*.framework")):
        run("codesign", "--force", "--sign", "-", str(framework))
    run("codesign", "--force", "--sign", "-", "--entitlements",
        str(ROOT / "macos/Runner/Release.entitlements"), str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    stage = ROOT / "build/ci-dmg"
    stage.mkdir()
    run("ditto", str(app), str(stage / app.name))
    (stage / "Applications").symlink_to("/Applications")
    run("hdiutil", "create", "-volname", f"JHenTai-{version()}", "-srcfolder", str(stage),
        "-format", "UDZO", str(output_dir() / f"JHenTai-{version()}.dmg"))


def package_ios() -> None:
    apps = list((ROOT / "build/ios/iphoneos").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Expected exactly one iOS app")
    info = verify_plist(apps[0], "MinimumOSVersion")
    if tuple(map(int, info["MinimumOSVersion"].split("."))) < (15, 0):
        raise ValueError("Expected iOS 15.0 or newer minimum")
    # Package only the app, not the build tree, signing config or logs.
    stage = ROOT / "build/ci-ipa/Payload"
    stage.mkdir(parents=True)
    run("ditto", str(apps[0]), str(stage / apps[0].name))
    run("zip", "-qry", str(output_dir() / f"JHenTai-{version()}-unsigned.ipa"),
        "Payload", cwd=stage.parent)


def package_linux() -> None:
    arch = os.environ["LINUX_ARCH"]
    deb_arch = {"x64": "amd64", "arm64": "arm64"}[arch]
    native = subprocess.check_output(["dpkg", "--print-architecture"], text=True).strip()
    if native != deb_arch:
        raise ValueError("Linux runner architecture does not match package")
    stage = ROOT / f"build/ci-deb-{arch}"
    stage.mkdir()
    shutil.copytree(ROOT / f"build/linux/{arch}/release/bundle", stage / "opt/jhentai")
    shutil.copytree(ROOT / "linux/assets/DEBIAN", stage / "DEBIAN")
    for script in ("postinst", "postrm"):
        (stage / "DEBIAN" / script).chmod(0o755)
    control = stage / "DEBIAN/control"
    text = control.read_text(encoding="utf-8")
    text = re.sub(r"^Version:.*$", f"Version: {version()}", text, flags=re.M)
    text = re.sub(r"^Architecture:.*$", f"Architecture: {deb_arch}", text, flags=re.M)
    control.write_text(text, encoding="utf-8")
    for source, dest in ((ROOT / f"linux/assets/{IDENTITY}.desktop", stage / f"usr/share/applications/{IDENTITY}.desktop"),
                         (ROOT / "assets/icon/JHenTai_512.png", stage / f"usr/share/icons/hicolor/512x512/apps/{IDENTITY}.png")):
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
    package = output_dir() / f"JHenTai-{version()}-Linux-{arch}.deb"
    run("dpkg-deb", "--build", "--root-owner-group", str(stage), str(package))
    run("dpkg-deb", "--info", str(package))


def main() -> None:
    command = sys.argv[1]
    if command == "version":
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as handle:
            handle.write(f"value={version()}\n")
    elif command == "signing":
        restore_signing()
    elif command == "clean-signing":
        for target in signing_paths():
            target.unlink(missing_ok=True)
    else:
        {"apple-config": apple_config, "android": package_android,
         "macos": package_macos, "ios": package_ios, "linux": package_linux}[command]()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError):
        # Never print exception details that could include signing Secret data.
        print("Release configuration invalid; check target and required Secret fields.", file=sys.stderr)
        sys.exit(1)
