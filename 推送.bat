@echo off
chcp 65001 >nul
setlocal

cd /d "%~dp0"

echo ============================================
echo   推送到 github.com/827388/ios-implant
echo ============================================
echo.
echo 提交已经在本地做好了，现在只需要推送。
echo.
echo 如果弹出登录窗口，请填：
echo   用户名: 827388
echo   密码  : 你的 Personal Access Token（不是登录密码）
echo.
echo 没有 Token 的话，先去这里生成一个（勾选 repo）：
echo   https://github.com/settings/tokens
echo.

git push -u origin main

if errorlevel 1 (
    echo.
    echo ============================================
    echo   推送失败，按提示选一个解决办法
    echo ============================================
    echo.
    echo [A] 用 Token 重试：
    echo     git remote set-url origin https://你的用户名:你的Token@github.com/827388/ios-implant.git
    echo     git push -u origin main
    echo.
    echo [B] 用 GitHub Desktop（不用敲命令）：
    echo     下载 https://desktop.github.com
    echo     File - Add local repository - 选这个文件夹
    echo     右上角 Publish repository 或 Push origin
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   推送成功
echo ============================================
echo.
echo 下一步：
echo   1. 打开 https://github.com/827388/ios-implant/actions
echo   2. 左侧点 build-implant
echo   3. 右侧 Run workflow - 绿色按钮
echo   4. 等 1-2 分钟
echo   5. 进这次运行，页面底部 Artifacts 下载 SpringBoardTweak-dylib.zip
echo   6. 解压后把 .dylib 放到
echo      C:\Users\ss827\Documents\deepseek-harness\default-workspace\
echo.
pause
