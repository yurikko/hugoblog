#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

static NSString *RunCommand(NSString *launchPath, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return nil;
    }

    if (task.terminationStatus != 0) {
        return nil;
    }

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *FirstMatch(NSString *text, NSString *pattern) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if (error || !regex) return nil;

    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges < 2) return nil;

    NSRange captureRange = [match rangeAtIndex:1];
    if (captureRange.location == NSNotFound) return nil;
    return [text substringWithRange:captureRange];
}

static NSDictionary *BatteryStatus(void) {
    NSString *output = RunCommand(@"/usr/bin/pmset", @[@"-g", @"batt"]);
    if (!output) {
        return @{@"percentage": [NSNull null], @"charging": [NSNull null], @"powerSource": [NSNull null]};
    }

    NSString *percentageText = FirstMatch(output, @"(\\d+)%");
    NSString *state = [[FirstMatch(output, @"\\d+%;\\s*([^;]+);") ?: @"" lowercaseString] copy];
    NSString *source = FirstMatch(output, @"Now drawing from '([^']+)'");

    NSNumber *percentage = percentageText ? @([percentageText integerValue]) : (NSNumber *)[NSNull null];
    id charging = state.length > 0 ? @([state containsString:@"charging"] || [state containsString:@"ac attached"]) : [NSNull null];

    return @{
        @"percentage": percentage ?: [NSNull null],
        @"charging": charging ?: [NSNull null],
        @"powerSource": source ?: (id)[NSNull null]
    };
}

static NSDictionary *MemoryStatus(void) {
    NSString *totalText = RunCommand(@"/usr/sbin/sysctl", @[@"-n", @"hw.memsize"]);
    NSString *vmStat = RunCommand(@"/usr/bin/vm_stat", @[]);
    if (!totalText || !vmStat) {
        return @{@"usedGB": [NSNull null], @"totalGB": [NSNull null], @"pressure": [NSNull null]};
    }

    double totalBytes = [totalText doubleValue];
    NSString *pageSizeText = FirstMatch(vmStat, @"page size of (\\d+) bytes");
    double pageSize = pageSizeText ? [pageSizeText doubleValue] : 4096.0;

    NSArray<NSString *> *keys = @[@"Pages active", @"Pages wired down", @"Pages occupied by compressor"];
    double usedPages = 0;
    for (NSString *key in keys) {
        NSString *escaped = [NSRegularExpression escapedPatternForString:key];
        NSString *value = FirstMatch(vmStat, [NSString stringWithFormat:@"%@:\\s+(\\d+)\\.", escaped]);
        usedPages += value ? [value doubleValue] : 0;
    }

    double usedBytes = usedPages * pageSize;
    double usedGB = round((usedBytes / pow(1024.0, 3)) * 10.0) / 10.0;
    double totalGB = round((totalBytes / pow(1024.0, 3)) * 10.0) / 10.0;
    double pressure = totalBytes > 0 ? round((usedBytes / totalBytes) * 1000.0) / 10.0 : 0;

    return @{
        @"usedGB": @(usedGB),
        @"totalGB": @(totalGB),
        @"pressure": @(pressure)
    };
}

@interface LocalHTTPServer : NSObject
@property (nonatomic, copy) NSDictionary *(^payloadProvider)(void);
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, strong) dispatch_source_t acceptSource;
- (BOOL)startOnPort:(uint16_t)port;
- (void)stop;
@end

@implementation LocalHTTPServer

- (BOOL)startOnPort:(uint16_t)port {
    self.serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (self.serverSocket < 0) return NO;

    int yes = 1;
    setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(self.serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
        return NO;
    }

    if (listen(self.serverSocket, 16) < 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
        return NO;
    }

    dispatch_queue_t queue = dispatch_queue_create("io.yurikko.mac-activity.http", DISPATCH_QUEUE_CONCURRENT);
    self.acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.serverSocket, 0, queue);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.acceptSource, ^{
        [weakSelf acceptConnection];
    });
    dispatch_source_set_cancel_handler(self.acceptSource, ^{
        if (weakSelf.serverSocket >= 0) {
            close(weakSelf.serverSocket);
            weakSelf.serverSocket = -1;
        }
    });
    dispatch_resume(self.acceptSource);
    return YES;
}

- (void)acceptConnection {
    int client = accept(self.serverSocket, NULL, NULL);
    if (client < 0) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char buffer[4096];
        ssize_t length = read(client, buffer, sizeof(buffer) - 1);
        if (length <= 0) {
            close(client);
            return;
        }

        buffer[length] = '\0';
        NSString *request = [NSString stringWithUTF8String:buffer] ?: @"";
        NSString *path = [self pathFromRequest:request];
        NSData *response = [self responseForPath:path];
        write(client, response.bytes, response.length);
        close(client);
    });
}

- (NSString *)pathFromRequest:(NSString *)request {
    NSArray<NSString *> *lines = [request componentsSeparatedByString:@"\r\n"];
    NSString *firstLine = lines.firstObject ?: @"";
    NSArray<NSString *> *parts = [firstLine componentsSeparatedByString:@" "];
    return parts.count > 1 ? parts[1] : @"/";
}

- (NSData *)responseForPath:(NSString *)path {
    NSData *body = nil;
    NSString *status = @"200 OK";

    if ([path isEqualToString:@"/api/activity"] || [path isEqualToString:@"/api/activity/"]) {
        NSDictionary *payload = self.payloadProvider ? self.payloadProvider() : @{};
        body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    } else if ([path isEqualToString:@"/api/health"] || [path isEqualToString:@"/api/health/"]) {
        body = [NSJSONSerialization dataWithJSONObject:@{@"ok": @YES} options:0 error:nil];
    } else {
        status = @"404 Not Found";
        body = [NSJSONSerialization dataWithJSONObject:@{@"error": @"Not found"} options:0 error:nil];
    }

    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 %@\r\n"
        @"Content-Type: application/json; charset=utf-8\r\n"
        @"Content-Length: %lu\r\n"
        @"Cache-Control: no-store\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Connection: close\r\n\r\n",
        status,
        (unsigned long)body.length
    ];

    NSMutableData *response = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [response appendData:body];
    return response;
}

- (void)stop {
    if (self.acceptSource) {
        dispatch_source_cancel(self.acceptSource);
        self.acceptSource = nil;
    } else if (self.serverSocket >= 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) LocalHTTPServer *server;
@property (nonatomic, copy) NSDictionary *latestPayload;
@property (nonatomic, strong) NSMenuItem *appNameItem;
@property (nonatomic, strong) NSMenuItem *memoryItem;
@property (nonatomic, strong) NSMenuItem *batteryItem;
@property (nonatomic, strong) NSMenuItem *serverItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.latestPayload = @{
        @"host": NSProcessInfo.processInfo.hostName ?: @"localhost",
        @"frontmostApp": [NSNull null],
        @"memory": MemoryStatus(),
        @"battery": BatteryStatus()
    };

    [self setupStatusItem];
    [self setupMenu];
    [self startServer];
    [self refresh:nil];

    self.timer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    [self.server stop];
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"desktopcomputer" accessibilityDescription:@"Mac Activity"];
    self.statusItem.button.title = @" Mac";
}

- (void)setupMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    self.appNameItem = [[NSMenuItem alloc] initWithTitle:@"当前应用：--" action:nil keyEquivalent:@""];
    self.memoryItem = [[NSMenuItem alloc] initWithTitle:@"内存：--" action:nil keyEquivalent:@""];
    self.batteryItem = [[NSMenuItem alloc] initWithTitle:@"电量：--" action:nil keyEquivalent:@""];
    self.serverItem = [[NSMenuItem alloc] initWithTitle:@"接口：启动中…" action:nil keyEquivalent:@""];

    [menu addItem:self.appNameItem];
    [menu addItem:self.memoryItem];
    [menu addItem:self.batteryItem];
    [menu addItem:self.serverItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *openSite = [[NSMenuItem alloc] initWithTitle:@"打开本地博客" action:@selector(openLocalSite:) keyEquivalent:@""];
    openSite.target = self;
    [menu addItem:openSite];

    NSMenuItem *copyEndpoint = [[NSMenuItem alloc] initWithTitle:@"复制接口地址" action:@selector(copyEndpoint:) keyEquivalent:@""];
    copyEndpoint.target = self;
    [menu addItem:copyEndpoint];

    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:@"立即刷新" action:@selector(refresh:) keyEquivalent:@"r"];
    refreshItem.target = self;
    [menu addItem:refreshItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)startServer {
    self.server = [[LocalHTTPServer alloc] init];
    __weak typeof(self) weakSelf = self;
    self.server.payloadProvider = ^NSDictionary *{
        return weakSelf.latestPayload ?: @{};
    };

    if ([self.server startOnPort:48123]) {
        self.serverItem.title = @"接口：http://127.0.0.1:48123/api/activity";
    } else {
        self.serverItem.title = @"接口启动失败：48123 端口已占用";
    }
}

- (void)refresh:(id)sender {
    NSString *appName = NSWorkspace.sharedWorkspace.frontmostApplication.localizedName;
    NSDictionary *memory = MemoryStatus();
    NSDictionary *battery = BatteryStatus();

    self.latestPayload = @{
        @"host": NSProcessInfo.processInfo.hostName ?: @"localhost",
        @"frontmostApp": appName ?: (id)[NSNull null],
        @"memory": memory,
        @"battery": battery
    };

    self.appNameItem.title = [NSString stringWithFormat:@"当前应用：%@", appName ?: @"未获取到应用"];
    self.memoryItem.title = [NSString stringWithFormat:@"内存：%@", [self formattedMemory:memory]];
    self.batteryItem.title = [NSString stringWithFormat:@"电量：%@", [self formattedBattery:battery]];
    self.statusItem.button.title = [NSString stringWithFormat:@" %@", [self shortLabelForAppName:appName ?: @"Mac"]];
}

- (NSString *)formattedMemory:(NSDictionary *)memory {
    id used = memory[@"usedGB"];
    id total = memory[@"totalGB"];
    if (![used isKindOfClass:[NSNumber class]] || ![total isKindOfClass:[NSNumber class]]) {
        return @"--";
    }
    return [NSString stringWithFormat:@"%.1f / %.1f GB", [used doubleValue], [total doubleValue]];
}

- (NSString *)formattedBattery:(NSDictionary *)battery {
    id percentage = battery[@"percentage"];
    if (![percentage isKindOfClass:[NSNumber class]]) {
        return @"--";
    }

    BOOL charging = [battery[@"charging"] isKindOfClass:[NSNumber class]] ? [battery[@"charging"] boolValue] : NO;
    return charging
        ? [NSString stringWithFormat:@"%@%% 充电中", percentage]
        : [NSString stringWithFormat:@"%@%%", percentage];
}

- (NSString *)shortLabelForAppName:(NSString *)appName {
    if (appName.length <= 8) return appName;
    return [[appName substringToIndex:8] stringByAppendingString:@"…"];
}

- (void)openLocalSite:(id)sender {
    NSURL *url = [NSURL URLWithString:@"http://localhost:1313"];
    if (url) {
        [NSWorkspace.sharedWorkspace openURL:url];
    }
}

- (void)copyEndpoint:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:@"http://127.0.0.1:48123/api/activity" forType:NSPasteboardTypeString];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
