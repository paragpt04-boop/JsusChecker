import sys
from datetime import datetime, timedelta

SECRET = 'JsusChecker2026_X9K#mP@zQ7_SECRETO'

def dart_hash(data):
    h = 5381
    for ch in data:
        h = ((h << 5) + h + ord(ch)) & 0xFFFFFFFF
    return h

def gen(device_id, days=30):
    expiry = datetime.now() + timedelta(days=days)
    exp = expiry.strftime('%Y%m%d')
    data = f"{device_id}:{exp}:{SECRET}"
    h = dart_hash(data)
    h_str = format(abs(h), '036') if h > 0 else format(abs(h) + 0xFFFFFFFF, '036')
    # Convert to base36
    chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    n = abs(h)
    result = ''
    while n > 0:
        result = chars[n % 36] + result
        n //= 36
    result = result.zfill(15)
    return f"JSUS-{result[0:5]}-{result[5:10]}-{result[10:15]}-{exp}"

def verify(device_id, key):
    try:
        parts = key.upper().split('-')
        if len(parts) != 5 or parts[0] != 'JSUS':
            return False, "Formato inválido"
        exp = parts[4]
        exp_date = datetime(int(exp[0:4]), int(exp[4:6]), int(exp[6:8]))
        if exp_date < datetime.now():
            return False, "Clave vencida"
        expected = gen(device_id, (exp_date - datetime.now()).days + 1)
        # Recalculate for exact date
        data = f"{device_id}:{exp}:{SECRET}"
        h = dart_hash(data)
        chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        n = abs(h)
        result = ''
        while n > 0:
            result = chars[n % 36] + result
            n //= 36
        result = result.zfill(15)
        expected = f"JSUS-{result[0:5]}-{result[5:10]}-{result[10:15]}-{exp}"
        if key.upper() == expected:
            return True, f"Válida hasta {exp_date.strftime('%d/%m/%Y')}"
        return False, "Clave incorrecta"
    except Exception as e:
        return False, str(e)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("═══ JsusChecker Key Generator ═══")
        print("Uso:")
        print("  Generar: python3 genkey.py <device_id> [dias]")
        print("  Verificar: python3 genkey.py verify <device_id> <key>")
        print("\nEjemplo:")
        did = "JSUS1ABC123"
        k = gen(did, 30)
        print(f"Device ID: {did}")
        print(f"Clave 30 días: {k}")
        ok, msg = verify(did, k)
        print(f"Verificación: {'✓' if ok else '✗'} {msg}")
    elif sys.argv[1] == 'verify':
        ok, msg = verify(sys.argv[2], sys.argv[3])
        print(f"{'✓ VÁLIDA' if ok else '✗ INVÁLIDA'}: {msg}")
    else:
        dias = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        k = gen(sys.argv[1], dias)
        print(f"Clave ({dias} días): {k}")
