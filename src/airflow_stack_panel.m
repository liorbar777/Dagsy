#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

static const CGFloat kPanelWidth = 520.0;
static const CGFloat kPanelMinHeight = 180.0;
static const CGFloat kPanelMaxHeight = 620.0;
static const CGFloat kPanelGap = 14.0;
static const CGFloat kCardGap = 10.0;
static const CGFloat kRightMargin = 16.0;
static const CGFloat kBottomMargin = 24.0;
static const CGFloat kCardHeight = 240.0;
static const CGFloat kHeaderHeight = 98.0;
static const CGFloat kScrollFooterHeight = 22.0;

@interface FlippedView : NSView
@end

@implementation FlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface PanelController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, copy) NSString *panelKind;
@property (nonatomic, copy) NSString *statePath;
@property (nonatomic, copy) NSString *runtimePath;
@property (nonatomic, copy) NSString *otherRuntimePath;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *lastSignature;
@property (nonatomic, assign) BOOL applyingLayout;
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSView *cardView;
@property (nonatomic, strong) NSView *accentView;
@end

@implementation PanelController

- (instancetype)initWithPanelKind:(NSString *)panelKind statePath:(NSString *)statePath {
    self = [super init];
    if (self) {
        _panelKind = [panelKind copy];
        _statePath = [statePath copy];
        NSString *baseDir = [statePath stringByDeletingLastPathComponent];
        NSString *runtimeName = [panelKind isEqualToString:@"success"] ? @"success_panel_runtime.json" : @"failure_panel_runtime.json";
        NSString *otherRuntimeName = [panelKind isEqualToString:@"success"] ? @"failure_panel_runtime.json" : @"success_panel_runtime.json";
        _runtimePath = [baseDir stringByAppendingPathComponent:runtimeName];
        _otherRuntimePath = [baseDir stringByAppendingPathComponent:otherRuntimeName];
    }
    return self;
}

- (NSDictionary<NSString *, id> *)theme {
    if ([self.panelKind isEqualToString:@"success"]) {
        return @{
            @"title": @"Airflow Successes",
            @"surface": [NSColor colorWithCalibratedRed:0.94 green:0.99 blue:0.95 alpha:1.0],
            @"border": [NSColor colorWithCalibratedRed:0.73 green:0.97 blue:0.82 alpha:1.0],
            @"accent": [NSColor colorWithCalibratedRed:0.09 green:0.40 blue:0.20 alpha:1.0],
            @"button": [NSColor colorWithCalibratedRed:0.09 green:0.40 blue:0.20 alpha:1.0],
        };
    }
    return @{
        @"title": @"Airflow Failures",
        @"surface": [NSColor colorWithCalibratedRed:1.0 green:0.96 blue:0.95 alpha:1.0],
        @"border": [NSColor colorWithCalibratedRed:0.96 green:0.78 blue:0.76 alpha:1.0],
        @"accent": [NSColor colorWithCalibratedRed:0.71 green:0.14 blue:0.09 alpha:1.0],
        @"button": [NSColor colorWithCalibratedRed:0.71 green:0.14 blue:0.09 alpha:1.0],
    };
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [self refresh:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];

    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqualToString:@"q"]) {
            [self.window close];
            return nil;
        }
        return event;
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)windowDidMove:(NSNotification *)notification {
    if (self.applyingLayout) {
        return;
    }
    [self writeRuntimeVisible:YES minimized:NO x:0 y:0];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self writeRuntimeVisible:NO minimized:NO x:0 y:0];
}

- (NSDictionary *)loadJSONFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [payload isKindOfClass:[NSDictionary class]] ? payload : nil;
}

- (void)writeJSON:(NSDictionary *)payload toPath:(NSString *)path {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) {
        return;
    }
    NSString *tempPath = [path stringByAppendingString:@".tmp"];
    [data writeToFile:tempPath atomically:YES];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:path error:nil];
}

- (void)writeRuntimeVisible:(BOOL)visible minimized:(BOOL)minimized x:(CGFloat)x y:(CGFloat)y {
    NSDictionary *payload = @{
        @"visible": @(visible),
        @"minimized": @(minimized),
        @"x": @(x),
        @"y": @(y),
        @"height": @(self.window.frame.size.height),
        @"updatedAt": @([[NSDate date] timeIntervalSince1970]),
    };
    [self writeJSON:payload toPath:self.runtimePath];
}

- (NSDictionary *)loadRuntime:(NSString *)path {
    NSDictionary *runtime = [self loadJSONFile:path];
    return runtime ?: @{};
}

- (BOOL)hasVisibleItemsForStatePath:(NSString *)path {
    NSDictionary *payload = [self loadJSONFile:path];
    if (!payload) {
        return NO;
    }
    NSArray *items = payload[@"items"];
    return [items isKindOfClass:[NSArray class]] && items.count > 0;
}

- (NSArray<NSDictionary *> *)loadItems {
    NSDictionary *payload = [self loadJSONFile:self.statePath];
    if (!payload) {
        return @[];
    }
    NSArray *items = payload[@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

- (NSString *)environmentLabel {
    NSDictionary *payload = [self loadJSONFile:self.statePath];
    NSString *label = [payload[@"environmentLabel"] isKindOfClass:[NSString class]] ? payload[@"environmentLabel"] : @"";
    return label.length > 0 ? label : @"local";
}

- (void)dismissItem:(NSString *)tokenOrRunId {
    NSDictionary *payload = [self loadJSONFile:self.statePath];
    if (!payload) {
        return;
    }
    NSArray *items = [payload[@"items"] isKindOfClass:[NSArray class]] ? payload[@"items"] : @[];
    NSMutableArray *nextItems = [NSMutableArray array];
    BOOL removed = NO;
    for (NSDictionary *item in items) {
        NSString *key = item[@"token"] ?: item[@"runId"] ?: @"";
        if (!removed && [key isEqualToString:tokenOrRunId]) {
            removed = YES;
            continue;
        }
        [nextItems addObject:item];
    }
    NSMutableDictionary *nextPayload = [payload mutableCopy];
    nextPayload[@"items"] = nextItems;
    [self writeJSON:nextPayload toPath:self.statePath];
}

- (void)openURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (NSString *)itemTitle:(NSDictionary *)item {
    if ([self.panelKind isEqualToString:@"success"]) {
        NSString *title = item[@"title"];
        if (title.length > 0) {
            return title;
        }
        return item[@"dagId"] ?: @"<unknown dag>";
    }
    return item[@"title"] ?: @"Airflow failure";
}

- (NSString *)itemBody:(NSDictionary *)item {
    if ([self.panelKind isEqualToString:@"success"]) {
        NSString *message = item[@"message"];
        if (message.length > 0) {
            return message;
        }
        NSString *runId = item[@"runId"] ?: @"<unknown run>";
        NSString *endDate = item[@"endDate"] ?: @"unknown end time";
        return [NSString stringWithFormat:@"Run: %@\nFinished: %@", runId, endDate];
    }
    return item[@"message"] ?: @"";
}

- (NSString *)itemKey:(NSDictionary *)item {
    return item[@"token"] ?: item[@"runId"] ?: [NSUUID UUID].UUIDString;
}

- (NSView *)buildCardForItem:(NSDictionary *)item {
    NSDictionary *theme = [self theme];
    NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, kCardHeight)];
    card.wantsLayer = YES;
    card.layer.backgroundColor = [theme[@"surface"] CGColor];
    card.layer.borderColor = [theme[@"border"] CGColor];
    card.layer.borderWidth = 1.0;
    card.layer.cornerRadius = 12.0;

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 192, 432, 22)];
    title.stringValue = [self itemTitle:item];
    title.editable = NO;
    title.bezeled = NO;
    title.drawsBackground = NO;
    title.selectable = NO;
    title.font = [NSFont boldSystemFontOfSize:13];
    title.textColor = [NSColor colorWithCalibratedWhite:0.08 alpha:1.0];
    [card addSubview:title];

    NSTextField *body = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 72, 432, 124)];
    body.stringValue = [self itemBody:item];
    body.editable = NO;
    body.bezeled = NO;
    body.drawsBackground = NO;
    body.selectable = NO;
    body.font = [NSFont systemFontOfSize:12];
    body.textColor = [NSColor colorWithCalibratedWhite:0.2 alpha:1.0];
    body.lineBreakMode = NSLineBreakByWordWrapping;
    body.usesSingleLineMode = NO;
    body.maximumNumberOfLines = 0;
    [card addSubview:body];

    NSButton *dismiss = [[NSButton alloc] initWithFrame:NSMakeRect(362, 24, 84, 28)];
    dismiss.title = @"Dismiss";
    dismiss.bezelStyle = NSBezelStyleRounded;
    dismiss.target = self;
    dismiss.action = @selector(handleDismiss:);
    dismiss.toolTip = [self itemKey:item];
    [card addSubview:dismiss];

    NSButton *open = [[NSButton alloc] initWithFrame:NSMakeRect(230, 24, 120, 28)];
    open.title = @"Open in Airflow";
    open.bordered = NO;
    open.wantsLayer = YES;
    open.layer.backgroundColor = [theme[@"button"] CGColor];
    open.layer.cornerRadius = 8.0;
    open.contentTintColor = [NSColor whiteColor];
    open.target = self;
    open.action = @selector(handleOpen:);
    open.toolTip = (item[@"url"] ?: @"");
    [card addSubview:open];

    return card;
}

- (CGFloat)desiredHeightForItemCount:(NSUInteger)count {
    CGFloat cardsHeight = MAX(1, count) * kCardHeight + MAX(0, count - 1) * kCardGap;
    CGFloat height = kHeaderHeight + MIN(cardsHeight, 320.0) + kScrollFooterHeight;
    return MIN(MAX(height, kPanelMinHeight), kPanelMaxHeight);
}

- (void)layoutWindowContent {
    NSView *content = self.window.contentView;
    CGFloat contentWidth = content.frame.size.width;
    CGFloat contentHeight = content.frame.size.height;

    self.cardView.frame = NSMakeRect(10, 10, contentWidth - 20, contentHeight - 20);
    self.accentView.frame = NSMakeRect(0, self.cardView.frame.size.height - 6, self.cardView.frame.size.width, 6);
    self.titleLabel.frame = NSMakeRect(18, self.cardView.frame.size.height - 40, 320, 24);
    self.countLabel.frame = NSMakeRect(self.cardView.frame.size.width - 90, self.cardView.frame.size.height - 38, 70, 20);
    self.subtitleLabel.frame = NSMakeRect(18, self.cardView.frame.size.height - 62, self.cardView.frame.size.width - 36, 18);
    self.scrollView.frame = NSMakeRect(18, 18, self.cardView.frame.size.width - 36, self.cardView.frame.size.height - 92);
}

- (void)rebuildUI:(NSArray<NSDictionary *> *)items {
    for (NSView *subview in [self.documentView.subviews copy]) {
        [subview removeFromSuperview];
    }

    NSDictionary *theme = [self theme];
    NSString *environmentLabel = [self environmentLabel];
    self.titleLabel.stringValue = [NSString stringWithFormat:@"%@ [%@]", theme[@"title"], environmentLabel];
    self.subtitleLabel.stringValue = [NSString stringWithFormat:@"Newest first. %@ Airflow panel.", [environmentLabel capitalizedString]];
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu item%@", (unsigned long)items.count, items.count == 1 ? @"" : @"s"];

    CGFloat contentWidth = self.scrollView.contentSize.width;
    CGFloat cardsHeight = MAX(1, items.count) * kCardHeight + MAX(0, items.count - 1) * kCardGap;
    self.documentView.frame = NSMakeRect(0, 0, contentWidth, cardsHeight);

    CGFloat y = 0.0;
    for (NSDictionary *item in [items reverseObjectEnumerator]) {
        NSView *card = [self buildCardForItem:item];
        card.frame = NSMakeRect(0, y, contentWidth, kCardHeight);
        [self.documentView addSubview:card];
        y += kCardHeight + kCardGap;
    }

    CGFloat height = [self desiredHeightForItemCount:items.count];
    NSRect frame = self.window.frame;
    frame.size.height = height;
    frame.size.width = kPanelWidth;
    self.applyingLayout = YES;
    [self.window setFrame:frame display:YES];
    [self layoutWindowContent];
    contentWidth = self.scrollView.contentSize.width;
    self.documentView.frame = NSMakeRect(0, 0, contentWidth, cardsHeight);
    y = 0.0;
    for (NSView *subview in [self.documentView.subviews copy]) {
        [subview removeFromSuperview];
    }
    for (NSDictionary *item in [items reverseObjectEnumerator]) {
        NSView *card = [self buildCardForItem:item];
        card.frame = NSMakeRect(0, y, contentWidth, kCardHeight);
        [self.documentView addSubview:card];
        y += kCardHeight + kCardGap;
    }
    [[self.scrollView contentView] scrollToPoint:NSMakePoint(0, 0)];
    [self.scrollView reflectScrolledClipView:self.scrollView.contentView];
    [self positionWindowForCurrentState];
    self.applyingLayout = NO;
}

- (void)positionWindowForCurrentState {
    NSScreen *screen = [NSScreen mainScreen];
    if (!screen) {
        return;
    }
    NSRect visible = screen.visibleFrame;
    NSDictionary *myRuntime = [self loadRuntime:self.runtimePath];
    NSDictionary *otherRuntime = [self loadRuntime:self.otherRuntimePath];
    CGFloat width = self.window.frame.size.width;
    CGFloat height = self.window.frame.size.height;
    CGFloat x = visible.origin.x + visible.size.width - width - kRightMargin;
    CGFloat y = visible.origin.y + kBottomMargin;
    BOOL otherVisible = [otherRuntime[@"visible"] boolValue] && [self hasVisibleItemsForStatePath:[self.panelKind isEqualToString:@"success"] ? [self.statePath stringByReplacingOccurrencesOfString:@"success_panel_state.json" withString:@"failure_panel_state.json"] : [self.statePath stringByReplacingOccurrencesOfString:@"failure_panel_state.json" withString:@"success_panel_state.json"]];

    if (otherVisible) {
        if ([self.panelKind isEqualToString:@"success"]) {
            x -= (width + kPanelGap);
        }
    }

    x = MAX(visible.origin.x + 12.0, MIN(x, visible.origin.x + visible.size.width - width - 12.0));
    y = MAX(visible.origin.y + 12.0, MIN(y, visible.origin.y + visible.size.height - height - 12.0));
    [self.window setFrameOrigin:NSMakePoint(x, y)];
    [self writeRuntimeVisible:YES minimized:NO x:x y:y];
}

- (void)refresh:(id)sender {
    NSArray<NSDictionary *> *items = [self loadItems];
    NSString *signature = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:items options:0 error:nil] encoding:NSUTF8StringEncoding];
    if (items.count == 0) {
        [self writeRuntimeVisible:NO minimized:NO x:self.window.frame.origin.x y:self.window.frame.origin.y];
        [self.window orderOut:nil];
        return;
    }

    if (![signature isEqualToString:self.lastSignature]) {
        self.lastSignature = signature;
        [self rebuildUI:items];
    } else {
        [self positionWindowForCurrentState];
    }

    [NSApp activateIgnoringOtherApps:NO];
    [self.window orderFront:nil];
}

- (void)buildWindow {
    NSDictionary *theme = [self theme];
    NSRect rect = NSMakeRect(0, 0, kPanelWidth, 340);
    self.window = [[NSWindow alloc] initWithContentRect:rect
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = theme[@"title"];
    self.window.level = NSFloatingWindowLevel;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;

    NSView *content = [[NSView alloc] initWithFrame:rect];
    self.window.contentView = content;

    self.cardView = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, kPanelWidth - 20, rect.size.height - 20)];
    self.cardView.wantsLayer = YES;
    self.cardView.layer.backgroundColor = [theme[@"surface"] CGColor];
    self.cardView.layer.borderColor = [theme[@"border"] CGColor];
    self.cardView.layer.borderWidth = 1.0;
    self.cardView.layer.cornerRadius = 14.0;
    [content addSubview:self.cardView];

    self.accentView = [[NSView alloc] initWithFrame:NSMakeRect(0, self.cardView.frame.size.height - 6, self.cardView.frame.size.width, 6)];
    self.accentView.wantsLayer = YES;
    self.accentView.layer.backgroundColor = [theme[@"accent"] CGColor];
    [self.cardView addSubview:self.accentView];

    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(18, self.cardView.frame.size.height - 40, 320, 24)];
    self.titleLabel.editable = NO;
    self.titleLabel.bezeled = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.selectable = NO;
    self.titleLabel.font = [NSFont boldSystemFontOfSize:16];
    [self.cardView addSubview:self.titleLabel];

    self.countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(self.cardView.frame.size.width - 90, self.cardView.frame.size.height - 38, 70, 20)];
    self.countLabel.editable = NO;
    self.countLabel.bezeled = NO;
    self.countLabel.drawsBackground = NO;
    self.countLabel.selectable = NO;
    self.countLabel.alignment = NSTextAlignmentRight;
    self.countLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.countLabel.textColor = [NSColor colorWithCalibratedWhite:0.35 alpha:1.0];
    [self.cardView addSubview:self.countLabel];

    self.subtitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(18, self.cardView.frame.size.height - 62, self.cardView.frame.size.width - 36, 18)];
    self.subtitleLabel.editable = NO;
    self.subtitleLabel.bezeled = NO;
    self.subtitleLabel.drawsBackground = NO;
    self.subtitleLabel.selectable = NO;
    self.subtitleLabel.font = [NSFont systemFontOfSize:11];
    self.subtitleLabel.textColor = [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
    [self.cardView addSubview:self.subtitleLabel];

    NSView *document = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, self.cardView.frame.size.width - 36, 200)];
    self.documentView = document;

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(18, 18, self.cardView.frame.size.width - 36, self.cardView.frame.size.height - 92)];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.documentView = document;
    [self.cardView addSubview:self.scrollView];
}

- (void)handleDismiss:(NSButton *)sender {
    [self dismissItem:(sender.toolTip ?: @"")];
    [self refresh:nil];
}

- (void)handleOpen:(NSButton *)sender {
    [self openURL:(sender.toolTip ?: @"")];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *executable = [[[NSProcessInfo processInfo] arguments] firstObject];
        NSString *panelKind = [executable containsString:@"success"] ? @"success" : @"failure";
        NSString *statePath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil;
        if (statePath == nil) {
            return 2;
        }

        NSApplication *app = [NSApplication sharedApplication];
        PanelController *delegate = [[PanelController alloc] initWithPanelKind:panelKind statePath:statePath];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
