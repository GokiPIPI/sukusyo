import requests
import json

def test_capture():
    url = "http://127.0.0.1:8000/capture"
    payload = {
        "monitor_index": 1,
        "base_name": "test_shot",
        "quality": 85
    }
    try:
        response = requests.post(url, json=payload)
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_capture()
