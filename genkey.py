import hmac, hashlib, base64, sys
from datetime import datetime, timedelta

SECRET = "JsusChecker2026_X9K#mP@zQ7_SECRETO"

def gen(device_id, days=30):
    expiry = datetime.now() + timedelta(days=days)
    exp = expiry.strftime('%Y%m%d')
    data = f"{device_id}:{exp}"
    h = hmac.new(SECRET.encode(), data.encode(), hashlib.sha256).digest()
    b = base64.b32encode(h[:12]).decode().rstrip('=')
    return f"JSUS-{b[:5]}-{b[5:10]}-{b[10:15]}-{exp}"

def verify(device_id, key):
    try:
        parts = key.split('-')
        if len(parts) != 5 or parts[0] != 'JSUS': return False, "Formato inválido"
        exp = parts[4]
        exp_date = datetime.strptime(exp, '%Y%m%d')
        if exp_date < datetime.now(): return False, "Clave vencida"
        data = f"{device_id}:{exp}"
        h = hmac.new(SECRET.encode(), data.encode(), hashlib.sha256).digest()
        b = base64.b32encode(h[:12]).decode().rstrip('=')
        expected = f"JSUS-{b[:5]}-{b[5:10]}-{b[10:15]}-{exp}"
        if key == expected: return True, f"Válida hasta {exp_date.strftime('%d/%m/%Y')}"
        return False, "Clave incorrecta"
    except Exception as e:
        return False, str(e)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Uso: python3 genkey.py <device_id> [dias]")
        print("     python3 genkey.py verify <device_id> <key>")
        print("\nEjemplo:")
        did = "TEST123"
        k = gen(did)
        print(f"Device: {did}")
        print(f"Clave 30 días: {k}")
        ok, msg = verify(did, k)
        print(f"Verificación: {ok} — {msg}")
    elif sys.argv[1] == 'verify':
        ok, msg = verify(sys.argv[2], sys.argv[3])
        print(f"{'✓ VÁLIDA' if ok else '✗ INVÁLIDA'}: {msg}")
    else:
        dias = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        k = gen(sys.argv[1], dias)
        print(f"Clave ({dias} días): {k}")
