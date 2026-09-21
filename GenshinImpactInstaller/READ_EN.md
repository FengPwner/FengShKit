# Genshin Impact Cross-Platform Auto-Installer


## Introduction

This is an automated installation tool based on Shell and Python, designed to help players download and install Genshin Impact with a single click. The script supports cross-platform execution, automatically detecting the current operating system and processor architecture to download the corresponding official installation package.


## Core Features

Cross-Platform Support: Perfectly compatible with Windows (Git Bash/WSL) and Android (Termux) environments.

Smart Architecture Detection: Automatically detects device processor architecture (x86_64 or ARM64) to download matching packages.

Dynamic Script Generation: In Windows environments, it automatically builds and invokes a  .bat  script to execute download tasks.

Auto-Trigger Installation: After downloading, it automatically triggers the system installation interface on Android devices and opens the launcher installer on Windows.

Fallback for Unknown OS: When running on unsupported systems, it waits for 5 seconds and then automatically redirects to the official Genshin Impact website.

Native Python Validator: Includes a URL validation script written in pure native libraries, requiring no third-party dependencies to check link validity.


## File Structure

 Install_NoCN.sh : Main installation script, responsible for environment detection, downloading, and triggering installation.

 test_NoCN.py : Link validation tool, used to check if official APIs are valid before installation.

 README.md : Project documentation.


## Quick Start


1. Validate Download Links (Optional)

Before running the installation script, it is recommended to verify if the official links are available:
```
python test_NoCN.py
```
2. Run Installation Script

Grant execution permission to the script and run:
```
chmod +x Installer_NoCN.sh
./Install_NoXN.sh
```
## Execution Logic

Windows Environment: When``MINGW``,``CYGWIN``, or``MSYS``is detected, it generates``Genshin_Windows_Installer.bat``and runs it automatically in a separate window to download the PC launcher.

Linux / Android Environment: When  Linux  is detected, it determines the architecture based on the return value of ``uname -m``. x86_64 downloads the PC launcher, ARM64 downloads the Android APK, and triggers the installation interface via``am start``after downloading.

Other Systems: Unrecognized systems will trigger the fallback logic, prompting and redirecting to  [米哈游_CN](https://ys.mihoyo.com/)


## Important Notes

Permissions: When auto-triggering the installation interface on Android, please ensure you have allowed to "Install unknown apps" in system settings.

Launcher Limitation: The script only automatically downloads and opens the "Launcher Installer". The full game resources (tens of GBs) require players to manually click download within the launcher.

Security Warning: Do not modify the official API links in the script to avoid downloading tampered malicious files.
