from PIL import Image
import os

img = Image.open('android-icon/icon.png').convert('RGBA')
sizes = {'mipmap-mdpi':48,'mipmap-hdpi':72,'mipmap-xhdpi':96,'mipmap-xxhdpi':144,'mipmap-xxxhdpi':192}
base = 'android/app/src/main/res'
for f,s in sizes.items():
    p = f'{base}/{f}'
    os.makedirs(p, exist_ok=True)
    img.resize((s,s), Image.LANCZOS).save(f'{p}/ic_launcher.png')
    img.resize((s,s), Image.LANCZOS).save(f'{p}/ic_launcher_round.png')
    print(f'OK {f}')
