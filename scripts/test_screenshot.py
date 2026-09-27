import io
import json
import urllib.request
from PIL import Image, ImageDraw

def test_screenshot():
    # 1. Create a clean single-measure digital screenshot
    img = Image.new('RGB', (600, 300), color='white')
    draw = ImageDraw.Draw(img)
    # Staves
    for y in [70, 90, 110, 130, 150]:
        draw.line([(40, y), (560, y)], fill='black', width=2)
    # Barlines
    draw.line([(40, 70), (40, 150)], fill='black', width=2)
    draw.line([(560, 70), (560, 150)], fill='black', width=2)
    # 4 distinct notes: C4 (y=160), E4 (y=140), G4 (y=120), C5 (y=90)
    for x, y in [(140, 160), (240, 140), (340, 120), (440, 90)]:
        draw.ellipse([(x - 8, y - 7), (x + 8, y + 7)], fill='black')
        draw.line([(x + 8, y), (x + 8, y - 40)], fill='black', width=2)

    buf = io.BytesIO()
    img.save(buf, format='PNG')
    img_bytes = buf.getvalue()

    boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW'
    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="title"\r\n\r\nSingle Measure Digital Screenshot\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="file"; filename="screenshot.png"\r\n'
        f'Content-Type: image/png\r\n\r\n'
    ).encode('utf-8') + img_bytes + f'\r\n--{boundary}--\r\n'.encode('utf-8')

    req = urllib.request.Request(
        'http://127.0.0.1:8000/api/transcribe',
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary}'}
    )
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode())
        print('STATUS:', res['status'])
        print('ENGINE:', res['engine'])
        print('TITLE:', res['title'])
        print('NOTES COUNT:', res['notes_count'])
        print('MEASURES COUNT:', res['measures_count'])
        print('DURATION:', res['duration'])

if __name__ == '__main__':
    test_screenshot()
