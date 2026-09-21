import urllib.request
import urllib.error
import time

URLS = {
    "PC版启动器 (x86_64)": "https://ys-api.mihoyo.com/event/download_porter/link/ys_cn/official/pc_default",
    "Android版安装包 (ARM64)": "https://ys-api.mihoyo.com/event/download_porter/link/ys_cn/official/android_default"
}

def check_url(name, url):
    """
    使用原生 urllib 检查 URL 有效性
    """
    print(f"正在验证: {name}")
    print(f"URL: {url}")
    
    try:
        req = urllib.request.Request(url, method='GET') 
        
        req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')                
        
        response = urllib.request.urlopen(req, timeout=10)
                                
        response.close()
        
        print(f"[√] 成功! 链接有效且可访问。\n")
        return True

    except urllib.error.HTTPError as e:
        
        print(f"[X] HTTP 错误! 状态码: {e.code}")
        if e.code == 403:
            print("    提示: 可能是 IP 被限制或缺少 Referer，但在浏览器中通常可访问。")
        elif e.code == 405:
            print("    提示: 服务器禁止了该请求方法。")
        print()
        return False
        
    except urllib.error.URLError as e:
        
        print(f"[X] 网络错误! 原因: {e.reason}\n")
        return False
        
    except Exception as e:
        print(f"[X] 未知错误: {str(e)}\n")
        return False

def main():
    print("=" * 60)
    print("原神下载链接验证工具")
    print("=" * 60)
    print()
    
    success_count = 0
    total_count = len(URLS)
    
    for name, url in URLS.items():
        if check_url(name, url):
            success_count += 1
        
        time.sleep(0.5)
        
    print("-" * 60)
    print(f"验证完成: {success_count}/{total_count} 个链接有效。")
    print("=" * 60)

if __name__ == "__main__":
    main()
