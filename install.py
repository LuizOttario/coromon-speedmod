#!/usr/bin/env python3
"""Instalador do Coromon Speed Mod.

Uso:
  python3 install.py            instala (ou reinstala) o mod
  python3 install.py uninstall  restaura o jogo original

O mod troca o script de entrada (main.lu) dentro de Resources/resource.car por
um que carrega o speedmod.lua e depois roda o main original sem alterações.
Um backup do resource.car original fica ao lado dele.
Precisa do luac5.1 instalado (pacote lua51 no Arch/CachyOS).
"""
import hashlib, os, shutil, struct, subprocess, sys, tempfile

# outra pasta do jogo (outra biblioteca da Steam, Windows): COROMON_DIR=/caminho/Coromon python3 install.py
GAME = os.environ.get("COROMON_DIR") or os.path.expanduser("~/.local/share/Steam/steamapps/common/Coromon")
CAR = os.path.join(GAME, "Resources", "resource.car")
BACKUP = CAR + ".speedmod-backup"
HERE = os.path.dirname(os.path.abspath(__file__))
MOD_SRC = os.path.join(HERE, "speedmod.lua")
MOD_PARTS = [os.path.join(HERE, n) for n in ("speedmod.lua", "missions_data.lua", "assist_data.lua", "ui.lua", "notify.lua", "assist.lua", "hud.lua")]
MARKER = b"SpeedMod: carregado"  # vem do ui.lua


# ---------------------------------------------------------------- .car format
def parse_car(data):
    if data[:4] != b"rac\x01":
        raise SystemExit("resource.car com formato desconhecido")
    ver, idx_size, count = struct.unpack_from("<III", data, 4)
    p, entries = 16, []
    for _ in range(count):
        typ, off, nlen = struct.unpack_from("<III", data, p)
        name_start = p + 12
        name = data[name_start:name_start + nlen]
        p = name_start + ((nlen + 1 + 3) & ~3)
        tag, blen = struct.unpack_from("<II", data, off)
        real = struct.unpack_from("<I", data, off + 8)[0]
        entries.append({"name": name, "type": typ, "tag": tag,
                        "off_field": p - ((nlen + 1 + 3) & ~3) - 8,
                        "data": data[off + 12: off + 12 + real]})
    return ver, idx_size, p, entries


def build_car(data, idx_end, entries):
    out = bytearray(data[:idx_end])          # header + index (names unchanged)
    pos = idx_end
    blobs = []
    for e in entries:
        payload = e["data"]
        body = struct.pack("<I", len(payload)) + payload
        body += b"\0" * ((-len(body)) % 4)
        struct.pack_into("<I", out, e["off_field"], pos)
        blob = struct.pack("<II", e["tag"], len(body)) + body
        blobs.append(blob)
        pos += len(blob)
    return bytes(out) + b"".join(blobs)


# ------------------------------------------- Lua 5.1 bytecode size_t 8 -> 4
def convert_bytecode(b, to=4):
    st = b[8]
    p = 12
    out = bytearray(b[:12]); out[8] = to

    def take(n):
        nonlocal p
        v = b[p:p + n]; p += n; return v

    def i32():
        return struct.unpack("<i", take(4))[0]

    def sz():
        return struct.unpack("<Q" if st == 8 else "<I", take(st))[0]

    def w_i32(v): out.extend(struct.pack("<i", v))
    def w_sz(v): out.extend(struct.pack("<Q" if to == 8 else "<I", v))

    def string():
        n = sz(); w_sz(n)
        if n: out.extend(take(n))

    def fn():
        string(); w_i32(i32()); w_i32(i32()); out.extend(take(4))
        n = i32(); w_i32(n); out.extend(take(4 * n))
        n = i32(); w_i32(n)
        for _ in range(n):
            t = take(1); out.extend(t)
            if t[0] == 1: out.extend(take(1))
            elif t[0] == 3: out.extend(take(8))
            elif t[0] == 4: string()
            elif t[0] != 0: raise ValueError("constante inválida")
        n = i32(); w_i32(n)
        for _ in range(n): fn()
        n = i32(); w_i32(n); out.extend(take(4 * n))
        n = i32(); w_i32(n)
        for _ in range(n): string(); w_i32(i32()); w_i32(i32())
        n = i32(); w_i32(n)
        for _ in range(n): string()

    fn()
    assert p == len(b)
    return bytes(out)


def lua_escape(b):
    # \ddd com 3 dígitos sempre; dígitos literais também escapados (sem ambiguidade)
    s = []
    for c in b:
        if 32 <= c < 127 and c not in (34, 92) and not chr(c).isdigit():
            s.append(chr(c))
        else:
            s.append("\\%03d" % c)
    return "".join(s)


def make_new_main(orig_main):
    mod = "\n".join(open(p, encoding="utf-8").read() for p in MOD_PARTS)
    src = (
        "do\n" + mod + "\nend\n"
        "local __orig = \"" + lua_escape(orig_main) + "\"\n"
        "local __f = assert(loadstring(__orig))\n"
        "return __f(...)\n"
    )
    luac = shutil.which("luac5.1") or shutil.which("luac")
    if not luac:
        raise SystemExit("luac5.1 não encontrado (instale o pacote lua51)")
    with tempfile.TemporaryDirectory() as td:
        sp, op = os.path.join(td, "main.lua"), os.path.join(td, "main.luac")
        open(sp, "w", encoding="utf-8").write(src)
        subprocess.run([luac, "-s", "-o", op, sp], check=True)
        bc = open(op, "rb").read()
    if bc[:5] != b"\x1bLuaQ":
        raise SystemExit("o luac encontrado não é Lua 5.1")
    return convert_bytecode(bc, 4)


# ------------------------------------------------------------------ actions
def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def install():
    current = open(CAR, "rb").read()
    _, _, idx_end, entries = parse_car(current)
    main = next(e for e in entries if e["name"] == b"main.lu")
    if MARKER in main["data"]:
        if not os.path.exists(BACKUP):
            raise SystemExit("mod já instalado, mas o backup sumiu. Use 'Verificar integridade' na Steam.")
        print("Mod já instalado; reinstalando a partir do backup.")
        current = open(BACKUP, "rb").read()
        _, _, idx_end, entries = parse_car(current)
        main = next(e for e in entries if e["name"] == b"main.lu")
    else:
        # arquivo original (ou atualizado pela Steam): vira o novo backup
        shutil.copy2(CAR, BACKUP)
        print("Backup criado:", BACKUP)

    main["data"] = make_new_main(main["data"])
    new = build_car(current, idx_end, entries)

    # valida o resultado antes de gravar
    _, _, _, check = parse_car(new)
    assert len(check) == len(entries)
    for a, b in zip(check, entries):
        assert a["name"] == b["name"] and a["data"] == b["data"]

    tmp = CAR + ".tmp"
    with open(tmp, "wb") as f:
        f.write(new)
    os.replace(tmp, CAR)
    print("Mod instalado! Abra o jogo e aperte Home.")


def uninstall():
    if not os.path.exists(BACKUP):
        raise SystemExit("Backup não encontrado. Use 'Verificar integridade dos arquivos' na Steam.")
    shutil.copy2(BACKUP, CAR)
    os.remove(BACKUP)
    print("Jogo restaurado ao original.")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "uninstall":
        uninstall()
    else:
        install()
