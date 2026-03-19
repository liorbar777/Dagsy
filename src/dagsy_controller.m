#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@interface DagsyController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSView *cardView;
@property (nonatomic, assign) BOOL recenteringWindow;
@property (nonatomic, copy) NSString *serviceName;
@property (nonatomic, copy) NSString *plistPath;
@end

@implementation DagsyController

- (instancetype)init {
    self = [super init];
    if (self) {
        _serviceName = @"com.wix.local-airflow-watcher";
        _plistPath = [@"~/Library/LaunchAgents/com.wix.local-airflow-watcher.plist" stringByExpandingTildeInPath];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [self refreshStatus:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSTextField *)labelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.usesSingleLineMode = NO;
    return label;
}

- (NSButton *)makeButtonWithTitle:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (void)centerWindowAnimated {
    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    if (screen == nil) {
        return;
    }
    NSRect visible = screen.visibleFrame;
    NSRect frame = self.window.frame;
    NSPoint origin = NSMakePoint(
        visible.origin.x + floor((visible.size.width - frame.size.width) / 2.0),
        visible.origin.y + floor((visible.size.height - frame.size.height) / 2.0)
    );
    self.recenteringWindow = YES;
    [self.window setFrameOrigin:origin];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.recenteringWindow = NO;
    });
}

- (void)windowDidMove:(NSNotification *)notification {
    if (self.recenteringWindow) {
        return;
    }
    [self centerWindowAnimated];
}

- (void)buildWindow {
    NSRect rect = NSMakeRect(0, 0, 640, 420);
    self.window = [[NSWindow alloc] initWithContentRect:rect
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Dagsy: Your DAG Watcher";
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;
    self.window.minSize = NSMakeSize(640, 420);
    self.window.maxSize = NSMakeSize(640, 420);
    [self.window center];

    NSView *content = [[NSView alloc] initWithFrame:rect];
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.07 green:0.10 blue:0.16 alpha:1.0].CGColor;
    self.window.contentView = content;

    NSView *glowA = [[NSView alloc] initWithFrame:NSMakeRect(26, 250, 210, 130)];
    glowA.wantsLayer = YES;
    glowA.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.13 green:0.62 blue:0.96 alpha:0.20].CGColor;
    glowA.layer.cornerRadius = 32.0;
    [content addSubview:glowA];

    NSView *glowB = [[NSView alloc] initWithFrame:NSMakeRect(430, 40, 170, 120)];
    glowB.wantsLayer = YES;
    glowB.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.18 green:0.88 blue:0.52 alpha:0.18].CGColor;
    glowB.layer.cornerRadius = 28.0;
    [content addSubview:glowB];

    self.cardView = [[NSView alloc] initWithFrame:NSMakeRect(18, 18, 604, 384)];
    self.cardView.wantsLayer = YES;
    self.cardView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.94 green:0.97 blue:1.0 alpha:0.96].CGColor;
    self.cardView.layer.borderColor = [NSColor colorWithCalibratedRed:0.55 green:0.72 blue:0.96 alpha:1.0].CGColor;
    self.cardView.layer.borderWidth = 1.2;
    self.cardView.layer.cornerRadius = 26.0;
    [content addSubview:self.cardView];

    NSView *accent = [[NSView alloc] initWithFrame:NSMakeRect(0, 376, 604, 8)];
    accent.wantsLayer = YES;
    accent.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.05 green:0.36 blue:0.95 alpha:1.0].CGColor;
    [self.cardView addSubview:accent];

    NSView *orb = [[NSView alloc] initWithFrame:NSMakeRect(442, 236, 118, 118)];
    orb.wantsLayer = YES;
    orb.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.09 green:0.60 blue:0.95 alpha:0.16].CGColor;
    orb.layer.cornerRadius = 59.0;
    orb.layer.borderColor = [NSColor colorWithCalibratedRed:0.08 green:0.52 blue:0.91 alpha:0.35].CGColor;
    orb.layer.borderWidth = 1.0;
    [self.cardView addSubview:orb];

    NSView *orbCore = [[NSView alloc] initWithFrame:NSMakeRect(472, 266, 58, 58)];
    orbCore.wantsLayer = YES;
    orbCore.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.14 green:0.82 blue:0.55 alpha:0.85].CGColor;
    orbCore.layer.cornerRadius = 29.0;
    [self.cardView addSubview:orbCore];

    NSTextField *title = [self labelWithFrame:NSMakeRect(28, 304, 360, 40)
                                         text:@"Dagsy"
                                         font:[NSFont boldSystemFontOfSize:34]
                                        color:[NSColor colorWithCalibratedRed:0.06 green:0.10 blue:0.18 alpha:1.0]];
    [self.cardView addSubview:title];

    NSTextField *subtitle = [self labelWithFrame:NSMakeRect(30, 278, 320, 20)
                                            text:@"Your DAG watcher for local Airflow"
                                            font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
                                           color:[NSColor colorWithCalibratedRed:0.20 green:0.31 blue:0.49 alpha:1.0]];
    [self.cardView addSubview:subtitle];

    NSTextField *blurb = [self labelWithFrame:NSMakeRect(30, 204, 390, 64)
                                         text:@"One calm control panel for noisy DAGs. Start the watcher, let failures and recoveries surface, then get out of the way."
                                         font:[NSFont systemFontOfSize:14]
                                        color:[NSColor colorWithCalibratedWhite:0.26 alpha:1.0]];
    [self.cardView addSubview:blurb];

    self.statusLabel = [self labelWithFrame:NSMakeRect(30, 150, 420, 28)
                                        text:@"Checking listener status..."
                                        font:[NSFont boldSystemFontOfSize:18]
                                       color:[NSColor colorWithCalibratedWhite:0.12 alpha:1.0]];
    [self.cardView addSubview:self.statusLabel];

    self.detailLabel = [self labelWithFrame:NSMakeRect(30, 92, 534, 44)
                                        text:@""
                                        font:[NSFont systemFontOfSize:13]
                                       color:[NSColor colorWithCalibratedWhite:0.34 alpha:1.0]];
    [self.cardView addSubview:self.detailLabel];

    self.startButton = [self makeButtonWithTitle:@"Start Listener" action:@selector(startListener:) frame:NSMakeRect(30, 28, 140, 36)];
    self.startButton.wantsLayer = YES;
    self.startButton.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.60 blue:0.33 alpha:1.0].CGColor;
    self.startButton.layer.cornerRadius = 10.0;
    self.startButton.contentTintColor = [NSColor whiteColor];
    [self.cardView addSubview:self.startButton];

    self.stopButton = [self makeButtonWithTitle:@"Stop Listener" action:@selector(stopListener:) frame:NSMakeRect(184, 28, 136, 36)];
    self.stopButton.wantsLayer = YES;
    self.stopButton.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.78 green:0.25 blue:0.18 alpha:1.0].CGColor;
    self.stopButton.layer.cornerRadius = 10.0;
    self.stopButton.contentTintColor = [NSColor whiteColor];
    [self.cardView addSubview:self.stopButton];

    NSButton *quitButton = [self makeButtonWithTitle:@"Close" action:@selector(closeWindow:) frame:NSMakeRect(490, 28, 84, 36)];
    [self.cardView addSubview:quitButton];
}

- (NSString *)runShell:(NSString *)command status:(int *)status {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[@"-lc", command];
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        if (status) {
            *status = -1;
        }
        return error.localizedDescription ?: @"Failed to launch command.";
    }

    [task waitUntilExit];
    if (status) {
        *status = task.terminationStatus;
    }

    NSData *stdoutData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderrData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
    NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
    return stdoutText.length > 0 ? stdoutText : stderrText;
}

- (BOOL)isRunning {
    int status = 0;
    NSString *command = [NSString stringWithFormat:@"launchctl print gui/%d/%@ >/dev/null 2>&1", getuid(), self.serviceName];
    [self runShell:command status:&status];
    return status == 0;
}

- (void)refreshStatus:(id)sender {
    BOOL running = [self isRunning];
    self.statusLabel.stringValue = running ? @"Local watcher online" : @"Local watcher offline";
    self.detailLabel.stringValue = running
        ? @"Dagsy is watching local Airflow and ready to surface failures, recoveries, and manual-run completions."
        : @"The local watcher is stopped. Start it to bring Dagsy notifications back online.";
    self.startButton.enabled = !running;
    self.stopButton.enabled = running;
}

- (void)startListener:(id)sender {
    int status = 0;
    NSString *command = [NSString stringWithFormat:@"launchctl bootstrap gui/%d %@ && launchctl kickstart -k gui/%d/%@", getuid(), self.plistPath, getuid(), self.serviceName];
    NSString *result = [self runShell:command status:&status];
    if (status != 0) {
        self.detailLabel.stringValue = [NSString stringWithFormat:@"Start failed: %@", result];
    }
    [self refreshStatus:nil];
}

- (void)stopListener:(id)sender {
    int status = 0;
    NSString *command = [NSString stringWithFormat:@"launchctl bootout gui/%d %@", getuid(), self.plistPath];
    NSString *result = [self runShell:command status:&status];
    if (status != 0) {
        self.detailLabel.stringValue = [NSString stringWithFormat:@"Stop failed: %@", result];
    }
    [self refreshStatus:nil];
}

- (void)closeWindow:(id)sender {
    [self.window close];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        DagsyController *delegate = [[DagsyController alloc] init];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
