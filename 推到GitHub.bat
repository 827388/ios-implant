@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ============================================
echo   iOS 植入体 — 一键推到 GitHub
echo ============================================
echo.

cd /d "%~dp0"

if not exist ".github\workflows\build.yml" (
    echo [错误] 当前目录不对，请在 implant-repo 目录里运行这个脚本
    pause
    exit /b 1
)

echo 请先在你的 GitHub 账号上新建一个空仓库（不要勾选 README），
echo 然后把它 HTTPS 地址粘到这里。
echo.
echo 格式示例：
echo   https://github.com/你的用户名/ios-implant.git
echo.
set /p REPO_URL=仓库地址：

if "%REPO_URL%"=="" (
    echo [错误] 地址不能为空
    pause
    exit /b 1
)

echo.
echo [1/5] 初始化 git ...
if not exist ".git" (
    git init -q
    git branch -M main
) else (
    echo     已存在 .git，跳过
)

echo [2/5] 配置用户信息 ...
git config user.name "implant-builder" >nul
git config user.email "builder@local" >nul

echo [3/5] 添加文件 ...
git add -A

echo [4/5] 提交 ...
git commit -q -m "implant build setup" 2>nul
if errorlevel 1 (
    echo     没有新改动，跳过提交
)

echo [5/5] 推送 ...
git remote remove origin 2>nul
git remote add origin %REPO_URL%
git push -u origin main

if errorlevel 1 (
    echo.
    echo [推送失败] 常见原因：
    echo   1. 仓库地址写错了
    echo   2. 没登录 / 需要 Personal Access Token
    echo      - GitHub 已不支持密码推送，请用 Token 作为密码：
    echo        头像 - Settings - Developer settings - Personal access tokens
    echo        - Tokens(classic) - Generate new token - 勾选 repo
    echo      - 推送时用户名填 GitHub 用户名，密码填这个 Token
    echo   3. 网络问题，重试一次
    pause
    exit /b 1
)

echo.
echo ============================================
echo   推送成功
echo ============================================
echo.
echo 接下来：
echo   1. 打开 %REPO_URL%
echo   2. 点顶部 Actions
echo   3. 左侧点 build-implant
echo   4. 右侧 Run workflow - 绿色按钮
echo   5. 等 1-2 分钟，进这次运行，页面底部 Artifacts
echo      下载 SpringBoardTweak-dylib.zip
echo   6. 解压，把 .dylib 放到
echo      C:\Users\ss827\Documents\deepseek-harness\default-workspace\
echo.
pause
