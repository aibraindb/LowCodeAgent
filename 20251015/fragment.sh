#!/usr/bin/env bash
set -euo pipefail

# --------- INPUT ---------
MODEL_ID="${1:?usage: ./compose.sh <hf_model_id>}"
# accept accidental "models/<hf_id>" input
MODEL_ID="${MODEL_ID#models/}"

REPO_URL="${REPO_URL:-https://github.com/exchange.git}"
SAFE_NAME="$(echo "$MODEL_ID" | tr '/:' '__')"
WORKDIR="exchange-tmp"
VENV=".ml-venv"
UL_BRANCH="upload_$(date +%s)"
BATCH_N="${BATCH_N:-1}"           # number of parts per commit
# -------------------------

# --------- STORAGE / CACHES (prefer Seagate) ----------
: "${HF_HOME:=/Volumes/Seagate/hf_home}"
: "${HF_HUB_CACHE:=/Volumes/Seagate/hf_cache}"
: "${HUGGINGFACE_HUB_CACHE:=$HF_HUB_CACHE}"
: "${TRANSFORMERS_CACHE:=$HF_HUB_CACHE}"
: "${TMPDIR:=/Volumes/Seagate/tmp}"
export HF_HOME HF_HUB_CACHE HUGGINGFACE_HUB_CACHE TRANSFORMERS_CACHE TMPDIR
mkdir -p "$HF_HOME" "$HF_HUB_CACHE" "$TMPDIR"
# ------------------------------------------------------

# --------- TOOLS ----------
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python  >/dev/null 2>&1; then PY=python
else echo "Python not found"; exit 1
fi
command -v git >/dev/null
# --------------------------

# --------- VENV ----------
[ -d "$VENV" ] || "$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate" 2>/dev/null || source "$VENV/Scripts/activate" 2>/dev/null
"$PY" -m pip -q install --upgrade pip
"$PY" -m pip -q install "huggingface_hub>=0.23" "cryptography>=42.0.0"
# -------------------------

read -rs -p "Passphrase: " PASSPHRASE; echo

# --------- REPO PREP ----------
[ -d "$WORKDIR/.git" ] || git clone "$REPO_URL" "$WORKDIR"

# Git hygiene (avoid CRLF mangling & flaky HTTP)
git -C "$WORKDIR" config core.autocrlf false
git -C "$WORKDIR" config core.eol lf
git -C "$WORKDIR" config http.sslBackend secure-transport || true
git -C "$WORKDIR" config http.version HTTP/1.1
git -C "$WORKDIR" config pack.window 0
git -C "$WORKDIR" config pack.depth 0
git -C "$WORKDIR" config pack.threads 1
git -C "$WORKDIR" config core.compression 9
git -C "$WORKDIR" config http.expect false
git -C "$WORKDIR" config http.lowSpeedLimit 0
git -C "$WORKDIR" config http.lowSpeedTime 999999

mkdir -p "$WORKDIR/models/$SAFE_NAME" "$WORKDIR/tools"
DL_DIR="$WORKDIR/.hf-snap"; mkdir -p "$DL_DIR"
# -------------------------------

# --------- HF DOWNLOAD (direct to DL_DIR) ----------
"$PY" - "$MODEL_ID" "$DL_DIR" <<'PY'
import os, sys
from huggingface_hub import snapshot_download
# ensure caches/temp are honored
os.environ["HF_HOME"]              = os.getenv("HF_HOME", "/Volumes/Seagate/hf_home")
os.environ["HF_HUB_CACHE"]         = os.getenv("HF_HUB_CACHE", "/Volumes/Seagate/hf_cache")
os.environ["HUGGINGFACE_HUB_CACHE"]= os.environ["HF_HUB_CACHE"]
os.environ["TRANSFORMERS_CACHE"]   = os.environ["HF_HUB_CACHE"]
os.environ["TMPDIR"]               = os.getenv("TMPDIR", "/Volumes/Seagate/tmp")
snapshot_download(
    repo_id=sys.argv[1],
    local_dir=sys.argv[2],
    local_dir_use_symlinks=False,
    cache_dir=os.environ["HF_HUB_CACHE"],
    resume_download=True,
    max_workers=2,
)
PY
# ---------------------------------------------------

# --------- CHUNK + ENCRYPT LARGE FILES ----------
"$PY" - "$DL_DIR" "$WORKDIR/models/$SAFE_NAME" "$PASSPHRASE" <<'PY'
import os, sys, json, hashlib, base64, shutil
from pathlib import Path
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SRC=Path(sys.argv[1]); DEST=Path(sys.argv[2]); PW=sys.argv[3].encode()
BUF=1024*1024
def hb(s): s=s.lower(); return int(float(s[:-1])*1024**({"k":1,"m":2,"g":3}[s[-1]])) if s[-1] in "kmg" else int(s)
CHUNK=hb("50m"); THR=hb("25m")
def sha(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda:f.read(BUF), b""): h.update(b)
    return h.hexdigest()

def kdf(pw,salt,rounds=200_000):
    return PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=rounds).derive(pw)

DEST.mkdir(parents=True, exist_ok=True)
files=[p for p in SRC.rglob("*") if p.is_file()]
for fp in files:
    rel=fp.relative_to(SRC); outp=(DEST/rel.parent); outp.mkdir(parents=True, exist_ok=True)
    sz=fp.stat().st_size
    if sz<=THR:
        shutil.copy2(fp, outp/fp.name); continue
    base=fp.name; chunk_dir=outp/f"{base}.chunks"; chunk_dir.mkdir(parents=True, exist_ok=True)
    salt=os.urandom(16); key=kdf(PW, salt)
    man={"original_filename":base,"original_size":sz,"original_sha256":sha(fp),"chunk_size":CHUNK,"chunks":[],
         "encrypted":True,"kdf":{"algo":"PBKDF2-HMAC-SHA256","rounds":200000},"salt_b64":base64.b64encode(salt).decode()}
    with open(fp,"rb") as f:
        i=0
        while True:
            buf=f.read(CHUNK)
            if not buf: break
            nonce=os.urandom(12); ct=AESGCM(key).encrypt(nonce, buf, base.encode())
            part=f"{base}.part{i:04d}"
            (chunk_dir/part).write_bytes(nonce+ct)
            man["chunks"].append({"name":part,"size":len(ct),"nonce_b64":base64.b64encode(nonce).decode(),"sha256":hashlib.sha256(ct).hexdigest()})
            i+=1
    (chunk_dir/"manifest.json").write_text(json.dumps(man,indent=2),encoding="utf-8")
PY
# --------------------------------------------------

# --------- WRITE JOIN TOOL ----------
"$PY" - "$WORKDIR/tools/join_file.py" <<'PY'
from pathlib import Path
Path(__import__("sys").argv[1]).write_text("""#!/usr/bin/env python3
import argparse, base64, hashlib, json, pathlib, sys, getpass
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
BUF=1024*1024
def sha(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda:f.read(BUF), b""): h.update(b)
    return h.hexdigest()
def derive(pw,salt,rounds):
    return PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=rounds).derive(pw)
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("chunks_dir"); ap.add_argument("--out",default=None); ap.add_argument("--passphrase",default=None)
    a=ap.parse_args()
    d=pathlib.Path(a.chunks_dir)
    man=json.loads((d/"manifest.json").read_text(encoding="utf-8"))
    out=pathlib.Path(a.out or man["original_filename"])
    pw=(a.passphrase or getpass.getpass("Passphrase: ")).encode()
    salt=base64.b64decode(man["salt_b64"]); rounds=int(man["kdf"]["rounds"])
    key=derive(pw,salt,rounds)
    with open(out,"wb") as w:
        for ch in man["chunks"]:
            raw=(d/ch["name"]).read_bytes(); nonce,ct=raw[:12], raw[12:]
            if hashlib.sha256(ct).hexdigest()!=ch["sha256"]:
                print(f"Hash mismatch: {ch['name']}", file=sys.stderr); sys.exit(3)
            w.write(AESGCM(key).decrypt(nonce, ct, man["original_filename"].encode()))
    ok = out.stat().st_size==man["original_size"] and sha(out)==man["original_sha256"]
    if not ok: print("Integrity check failed.", file=sys.stderr); sys.exit(4)
    print(f"OK → {out} ({out.stat().st_size} bytes)")
if __name__=="__main__": main()
""")
PY
chmod +x "$WORKDIR/tools/join_file.py"
# -----------------------------------

# --------- ATTRS / IGNORE FIRST ----------
cat > "$WORKDIR/.gitattributes" <<'GITATTR'
*.part*        -text
*.chunks/**    -text
*.bin          -text
*.safetensors  -text
*.onnx         -text
*.h5           -text
*.pt           -text
*.ot           -text
*.msgpack      -text
*.model        -text
*.npy          -text
*.npz          -text
*.json         text eol=lf
*.txt          text eol=lf
*.md           text eol=lf
*.xml          text eol=lf
GITATTR

printf "%s\n%s\n%s\n%s\n%s\n%s\n%s\n" \
".ml-venv/" "__pycache__/" "*.cache/" "*.tmp" ".DS_Store" "hf-snap-*/" ".parts.*" > "$WORKDIR/.gitignore"
# -----------------------------------------

# --------- PUSH SEQUENCE ----------
cd "$WORKDIR"
git fetch origin || true
git checkout --orphan "$UL_BRANCH"
git rm -r --cached . 2>/dev/null || true
git add .gitattributes .gitignore tools/join_file.py
git commit -m "init: attributes/ignore + join tool"
git push -u origin "$UL_BRANCH"

# parts in tiny commits (to avoid 500s)
CNT=0
while IFS= read -r -d '' f; do
  git add "$f"; CNT=$((CNT+1))
  if [ "$CNT" -ge "$BATCH_N" ]; then
    git commit -m "$SAFE_NAME: add parts"
    git push origin "$UL_BRANCH"
    CNT=0
  fi
done < <(find "models/$SAFE_NAME" -type f -name "*.part*" -print0 | sort -z)
if [ "$CNT" -gt 0 ]; then
  git commit -m "$SAFE_NAME: add parts (tail)"
  git push origin "$UL_BRANCH"
fi

# manifests & small files
SMALL_FILES=$(find "models/$SAFE_NAME" -type f \( -name "manifest.json" -o -name "*.json" ! -name "*.part*" \) | sort)
if [ -n "${SMALL_FILES:-}" ]; then
  git add $SMALL_FILES
  git commit -m "$SAFE_NAME: add manifests & metadata" || true
  git push origin "$UL_BRANCH"
fi

# replace main with this upload
git push origin "$UL_BRANCH:main" --force
git push origin --delete "$UL_BRANCH" || true
echo "DONE: main now contains $SAFE_NAME from $MODEL_ID on $REPO_URL"
# ---------------------------------
