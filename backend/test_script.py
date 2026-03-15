import requests

try:
    url = "http://127.0.0.1:8000/images/y/screenshot_20260310_105704_01.jpg"
    print(f"Requesting {url}")
    r = requests.get(url)
    print("Status:", r.status_code)
    print("Headers:", r.headers)
except Exception as e:
    print("Error:", e)
