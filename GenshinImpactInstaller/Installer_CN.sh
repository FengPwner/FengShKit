#!/bin/bash

BAT_FILENAME="Genshin_Windows_Installer.bat"
URL_X86_64="https://ys-api.mihoyo.com/event/download_porter/link/ys_cn/official/pc_default"
URL_ARM="https://ys-api.mihoyo.com/event/download_porter/link/ys_cn/official/android_default"
OFFICIAL_WEBSITE="https://ys.mihoyo.com/"

OS_TYPE=$(uname -s)

if [[ "$OS_TYPE" == MINGW* ]] || [[ "$OS_TYPE" == CYGWIN* ]] || [[ "$OS_TYPE" == MSYS* ]]; then
    echo ">>> 检测到 Windows 环境，正在生成 $BAT_FILENAME ..."
    
    cat > "$BAT_FILENAME" <<EOF
@echo off
chcp 65001 >nul
echo ========================================
echo    原神 Windows 自动下载启动器
echo ========================================
echo.
echo [1/2] 正在下载官方启动器，请耐心等待...
curl -L -o Genshin_Impact_Setup.exe -# "$URL_X86_64"

if %errorlevel% equ 0 (
    echo.
    echo [2/2] 下载完成！正在启动安装程序...
    start Genshin_Impact_Setup.exe
) else (
    echo.
    echo [错误] 下载失败，请检查网络连接！
)
pause
EOF

    echo ">>> 生成成功！正在自动运行..."   

    WIN_BAT_PATH=$(cygpath -w "$BAT_FILENAME")
    cmd.exe /c start "" "$WIN_BAT_PATH"
    
    exit 0
fi

if [[ "$OS_TYPE" == "Linux" ]]; then
    echo ">>> 正在检测当前设备的处理器架构..."
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64|amd64)
            echo ">>> 检测到 x86_64 架构，准备下载 PC 版原神启动器..."
            URL="$URL_X86_64"
            FILENAME="Genshin_Impact_Setup.exe"
            ;;
        aarch64|armv8*)
            echo ">>> 检测到 ARM64 架构，准备下载 Android 版原神安装包..."
            URL="$URL_ARM"
            FILENAME="Genshin_Impact.apk"
            ;;
        *)
            echo ">>> 错误：不支持的处理器架构 ($ARCH)，退出脚本。"
            exit 1
            ;;
    esac

    echo ">>> 开始下载: $FILENAME"

    curl -L -O -# "$URL"

    if [ $? -eq 0 ]; then
        echo ">>> 下载完成！文件保存为: $FILENAME"
        
        if [[ "$FILENAME" == *.apk ]]; then
            echo ">>> 正在唤起安卓系统安装界面..."
            
            APK_PATH=$(pwd)/$FILENAME
            am start -a android.intent.action.VIEW -d "file://$APK_PATH" -t application/vnd.android.package-archive
        fi
                
        if [[ "$FILENAME" == *.sh || "$FILENAME" == *.AppImage ]]; then
            chmod +x "$FILENAME"
            echo ">>> 已赋予执行权限，你可以通过 ./$FILENAME 运行。"
        fi
    else
        echo ">>> 下载失败，请检查网络连接或下载链接是否有效。"
    fi
    exit 0
fi

echo ">>> 警告：无法识别当前操作系统 ($OS_TYPE)。"
echo ">>> 脚本将不会执行任何操作。"
echo ">>> 正在准备跳转到《原神》官方网站..."

if command -v xdg-open > /dev/null 2>&1; then
    xdg-open "$OFFICIAL_WEBSITE" &
elif command -v open > /dev/null 2>&1; then
    open "$OFFICIAL_WEBSITE" &
else
    echo ">>> 无法自动打开浏览器，请手动访问: $OFFICIAL_WEBSITE"
fi

echo ">>> 5秒后脚本将自动退出..."
sleep 5
exit 0
