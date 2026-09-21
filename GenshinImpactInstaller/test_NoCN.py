import urllib.request
import urllib.error
import time

URLS = {
    "PC Launcher (x86_64)": "https://sg-download-porter.hoyoverse.com/event/download_porter/link/genshin/official/pc_default",
    "Android APK (ARM64)": "https://sg-download-porter.hoyoverse.com/event/download_porter/link/genshin/official/android_default"
}

def check_url(name, url):
    print(f"Checking: {name}")
    print(f"URL: {url}")
    
    try:
        req = urllib.request.Request(url, method='GET')
        req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        
        response = urllib.request.urlopen(req, timeout=10)
        response.close()
        
        print("[OK] Link is valid and accessible.\n")
        return True

    except urllib.error.HTTPError as e:
        print(f"[FAIL] HTTP Error: {e.code}")
        if e.code == 403:
            print("    Tip: Access may be restricted. Try from a browser to verify.")
        elif e.code == 405:
            print("    Tip: The server does not allow this request method.")
        print()
        return False
        
    except urllib.error.URLError as e:
        print(f"[FAIL] Network Error: {e.reason}\n")
        return False
        
    except Exception as e:
        print(f"[FAIL] Unknown Error: {str(e)}\n")
        return False

def main():
    print("=" * 60)
    print("   Genshin Impact Global Link Validator")
    print("=" * 60)
    print()
    
    success_count = 0
    total_count = len(URLS)
    
    for name, url in URLS.items():
        if check_url(name, url):
            success_count += 1
        time.sleep(0.5)
        
    print("-" * 60)
    print(f"Verification complete: {success_count}/{total_count} link(s) valid.")
    print("=" * 60)

if __name__ == "__main__":
    main()
