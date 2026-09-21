#!/bin/bash

BAT_FILENAME="Genshin_Global_Windows_Installer.bat"

URL_X86_64="https://sg-download-porter.hoyoverse.com/event/download_porter/link/genshin/official/pc_default"
URL_ARM="https://sg-download-porter.hoyoverse.com/event/download_porter/link/genshin/official/android_default"
OFFICIAL_WEBSITE="https://genshin.hoyoverse.com/"

OS_TYPE=$(uname -s)

if [[ "$OS_TYPE" == MINGW* ]] || [[ "$OS_TYPE" == CYGWIN* ]] || [[ "$OS_TYPE" == MSYS* ]]; then
    echo ">>> Detected Windows environment. Generating $BAT_FILENAME ..."
        
    cat > "$BAT_FILENAME" <<EOF
@echo off
echo ==========================================
echo   Genshin Impact Global Installer (PC)
echo ==========================================
echo.
echo Downloading PC Launcher...
echo Target: %URL_X86_64%
echo.

powershell -Command "& {Invoke-WebRequest -Uri '%URL_X86_64%' -OutFile 'GenshinImpact_Global_Setup.exe'}"

if exist "GenshinImpact_Global_Setup.exe" (
    echo [SUCCESS] Download complete. Starting installer...
    start "" "GenshinImpact_Global_Setup.exe"
) else (
    echo [ERROR] Download failed. Please check your internet connection.
    pause
)
EOF

    echo ">>> Executing Windows installer script..."
    cmd.exe /c start "" "$BAT_FILENAME"
    exit 0

elif [[ "$OS_TYPE" == "Linux" ]]; then
    ARCH=$(uname -m)
    
    echo ">>> Detected Linux/Android environment."
    echo ">>> Architecture: $ARCH"

    if [[ "$ARCH" == "x86_64" ]]; then
        TARGET_URL="$URL_X86_64"
        FILENAME="GenshinImpact_Global_Setup.exe"
        echo ">>> Downloading PC Launcher for x86_64..."
        
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        TARGET_URL="$URL_ARM"
        FILENAME="GenshinImpact_Global_Android.apk"
        echo ">>> Downloading Android APK for ARM64..."
    else
        echo ">>> Unsupported architecture: $ARCH"
        echo ">>> Redirecting to official website in 5 seconds..."
        sleep 5
        if command -v xdg-open &> /dev/null; then
            xdg-open "$OFFICIAL_WEBSITE"
        fi
        exit 1
    fi
    
    if command -v curl &> /dev/null; then
        curl -L -o "$FILENAME" "$TARGET_URL"
    elif command -v wget &> /dev/null; then
        wget -O "$FILENAME" "$TARGET_URL"
    else
        echo ">>> Error: Neither curl nor wget found. Please install one of them."
        exit 1
    fi
    
    if [ -f "$FILENAME" ]; then
        echo "[SUCCESS] Download complete: $FILENAME"
               
        if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
            if command -v am &> /dev/null; then
                echo ">>> Triggering Android Package Installer..."
                am start -a android.intent.action.VIEW -d "file://$(pwd)/$FILENAME" -t application/vnd.android.package-archive
            fi
        else
            echo ">>> Please run the installer manually."
        fi
    else
        echo "[ERROR] Download failed."
    fi

else
    echo ">>> Unsupported OS: $OS_TYPE"
    echo ">>> Visit $OFFICIAL_WEBSITE for manual download."
fi
