"""Safely extracts, detects, and customizes an uploaded project. Runs inside the ephemeral runner."""
import os, re, sys, shutil, zipfile
from pathlib import Path
from xml.sax.saxutils import escape

MAX_FILES, MAX_FILE, MAX_TOTAL = 50000, 700 * 1024**2, 2 * 1024**3
E = os.environ


def fail(msg, code=2):
    print(f"::error::{msg}")
    sys.exit(code)


def safe_extract(zpath, dest):
    dest = dest.resolve()
    total = n = 0
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            n += 1
            if n > MAX_FILES:
                fail("Too many files in archive")
            name = info.filename.replace("\\", "/")
            if name.startswith("/") or re.match(r"^[A-Za-z]:", name) or ".." in name.split("/"):
                fail(f"Unsafe path in archive: {name}")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                fail(f"Symlink in archive: {name}")
            target = (dest / name).resolve()
            if dest != target and dest not in target.parents:
                fail(f"Path escapes project folder: {name}")
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            written = 0
            with z.open(info) as src, open(target, "wb") as out:
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    written += len(chunk)
                    total += len(chunk)
                    if written > MAX_FILE or total > MAX_TOTAL:
                        fail("Archive expands beyond allowed size")
                    out.write(chunk)


def find_root(base):
    items = [p for p in base.iterdir() if not p.name.startswith("__MACOSX")]
    return items[0] if len(items) == 1 and items[0].is_dir() else base


def detect(root):
    if (root / "pubspec.yaml").exists() and any(root.rglob("*.dart")):
        return "flutter"
    if any(root.rglob("AndroidManifest.xml")) and (any(root.rglob("build.gradle")) or any(root.rglob("build.gradle.kts"))):
        return "native"
    return "unsupported"


def app_gradle(root):
    for p in sorted(list(root.rglob("build.gradle")) + list(root.rglob("build.gradle.kts"))):
        t = p.read_text(errors="ignore")
        if "com.android.application" in t or "applicationId" in t:
            return p
    return None


def patch_gradle(path):
    t = path.read_text()
    t, n1 = re.subn(r"applicationId\s*=?\s*[\"'][^\"']+[\"']", f'applicationId = "{E["PACKAGE_NAME"]}"', t, count=1)
    if n1 == 0:
        fail("applicationId not found in the app Gradle file")
    # namespace is intentionally left untouched: code/manifest keep resolving against it.
    t = re.sub(r"versionCode\s*=?\s*[^\n]+", f'versionCode = {int(E["VERSION_CODE"])}', t, count=1)
    t = re.sub(r"versionName\s*=?\s*[^\n]+", f'versionName = "{E["VERSION_NAME"]}"', t, count=1)
    path.write_text(t)


def patch_manifest(root):
    for m in root.rglob("src/main/AndroidManifest.xml"):
        t = m.read_text()
        label = escape(E["APP_NAME"], {'"': "&quot;"})

        def fix(match):
            tag = match.group(0)
            tag = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', tag) if "android:label=" in tag else tag.replace("<application", f'<application android:label="{label}"', 1)
            return tag

        m.write_text(re.sub(r"<application\b[^>]*>", fix, t, count=1))
        return m
    return None


def make_icons(root, icon_path, manifest):
    from PIL import Image
    img = Image.open(icon_path).convert("RGBA")
    if img.width < 256 or abs(img.width - img.height) > img.width * 0.05:
        fail("Icon must be square and at least 256px")
    res = manifest.parent / "res"
    for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        out = res / f"mipmap-{d}"
        out.mkdir(parents=True, exist_ok=True)
        img.resize((px, px), Image.LANCZOS).save(out / "ic_launcher.png")
    for x in res.glob("mipmap-anydpi*/ic_launcher*.xml"):
        x.unlink()
    t = manifest.read_text()
    t = re.sub(r'\s+android:roundIcon="[^"]*"', "", t)
    t = re.sub(r'android:icon="[^"]*"', 'android:icon="@mipmap/ic_launcher"', t) if "android:icon=" in t else t.replace("<application", '<application android:icon="@mipmap/ic_launcher"', 1)
    manifest.write_text(t)


def main():
    work = Path(E["RUNNER_TEMP"]) / "work"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    safe_extract(Path(E["RUNNER_TEMP"]) / "in" / "source.zip", work)
    root = find_root(work)
    ptype = detect(root)
    if ptype == "unsupported":
        fail("Unsupported project: expected a Flutter project or a native Android Gradle project")
    gradle = app_gradle(root)
    if gradle is None:
        fail("Could not locate the Android app module")
    if ptype == "native" and not (gradle.parent.parent / "gradlew").exists() and not (root / "gradlew").exists():
        fail("Native projects must include the Gradle wrapper (gradlew)")
    patch_gradle(gradle)
    if ptype == "flutter":
        ps = root / "pubspec.yaml"
        t = ps.read_text()
        ps.write_text(re.sub(r"(?m)^version:.*$", f'version: {E["VERSION_NAME"]}+{int(E["VERSION_CODE"])}', t, count=1) if re.search(r"(?m)^version:", t) else t + f'\nversion: {E["VERSION_NAME"]}+{int(E["VERSION_CODE"])}\n')
    manifest = patch_manifest(root)
    if manifest is None:
        fail("AndroidManifest.xml not found in src/main")
    icon = Path(E["RUNNER_TEMP"]) / "in" / "icon.img"
    if icon.exists():
        make_icons(root, icon, manifest)
    project_dir = root if ptype == "flutter" else (gradle.parent.parent if (gradle.parent.parent / "gradlew").exists() else root)
    with open(E["GITHUB_OUTPUT"], "a") as f:
        f.write(f"project_type={ptype}\nproject_dir={project_dir}\n")
    print(f"Prepared {ptype} project at {project_dir}")


if __name__ == "__main__":
    main()
