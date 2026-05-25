import os

manifest_path = 'android/app/src/main/AndroidManifest.xml'
xml_dir = 'android/app/src/main/res/xml'
xml_path = f'{xml_dir}/network_security_config.xml'

os.makedirs(xml_dir, exist_ok=True)

with open('android_config/network_security_config.xml', 'r') as f:
    xml = f.read()
with open(xml_path, 'w') as f:
    f.write(xml)

with open(manifest_path, 'r') as f:
    manifest = f.read()

if 'usesCleartextTraffic' not in manifest:
    manifest = manifest.replace(
        '<application',
        '<application android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/network_security_config"',
        1)

perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.WAKE_LOCK',
    'android.permission.FOREGROUND_SERVICE',
]
for p in perms:
    tag = f'<uses-permission android:name="{p}"/>'
    if p not in manifest:
        manifest = manifest.replace('<application', tag + '\n    <application', 1)

with open(manifest_path, 'w') as f:
    f.write(manifest)

print("Manifest OK!")
