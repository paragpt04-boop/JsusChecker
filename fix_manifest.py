import os

manifest_path = 'android/app/src/main/AndroidManifest.xml'
xml_dir = 'android/app/src/main/res/xml'
xml_path = f'{xml_dir}/network_security_config.xml'

# Copy network security config
os.makedirs(xml_dir, exist_ok=True)
with open('android_config/network_security_config.xml', 'r') as f:
    xml = f.read()
with open(xml_path, 'w') as f:
    f.write(xml)
print("Network config copied")

# Fix manifest
with open(manifest_path, 'r') as f:
    manifest = f.read()

# Add cleartext and network config to application tag
if 'usesCleartextTraffic' not in manifest:
    manifest = manifest.replace(
        '<application',
        '<application android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/network_security_config"',
        1
    )
    print("Added cleartext traffic")

# Add INTERNET permission
if 'INTERNET' not in manifest:
    manifest = manifest.replace(
        '<application',
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <application',
        1
    )
    print("Added INTERNET permission")

with open(manifest_path, 'w') as f:
    f.write(manifest)
print("Manifest fixed!")
