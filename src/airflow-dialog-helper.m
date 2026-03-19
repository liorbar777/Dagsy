#import <AppKit/AppKit.h>

@interface PopupController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *urlText;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *result;
@end

@implementation PopupController

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                          url:(NSString *)url
                         kind:(NSString *)kind {
    self = [super init];
    if (self) {
        _titleText = [title copy];
        _messageText = [message copy];
        _urlText = [url copy];
        _kind = [kind copy];
        _result = @"Dismiss";
    }
    return self;
}

- (NSDictionary<NSString *, NSColor *> *)theme {
    if ([[self.kind lowercaseString] isEqualToString:@"failure"]) {
        return @{
            @"surface": [NSColor colorWithCalibratedRed:1.0 green:0.957 blue:0.949 alpha:1.0],
            @"border": [NSColor colorWithCalibratedRed:0.957 green:0.78 blue:0.765 alpha:1.0],
            @"accent": [NSColor colorWithCalibratedRed:0.706 green:0.137 blue:0.094 alpha:1.0],
            @"button": [NSColor colorWithCalibratedRed:0.706 green:0.137 blue:0.094 alpha:1.0]
        };
    }
    if ([[self.kind lowercaseString] isEqualToString:@"success"]) {
        return @{
            @"surface": [NSColor colorWithCalibratedRed:0.941 green:0.992 blue:0.949 alpha:1.0],
            @"border": [NSColor colorWithCalibratedRed:0.733 green:0.969 blue:0.816 alpha:1.0],
            @"accent": [NSColor colorWithCalibratedRed:0.086 green:0.396 blue:0.204 alpha:1.0],
            @"button": [NSColor colorWithCalibratedRed:0.086 green:0.396 blue:0.204 alpha:1.0]
        };
    }
    return @{
        @"surface": [NSColor colorWithCalibratedRed:0.937 green:0.965 blue:1.0 alpha:1.0],
        @"border": [NSColor colorWithCalibratedRed:0.749 green:0.859 blue:0.996 alpha:1.0],
        @"accent": [NSColor colorWithCalibratedRed:0.114 green:0.306 blue:0.847 alpha:1.0],
        @"button": [NSColor colorWithCalibratedRed:0.114 green:0.306 blue:0.847 alpha:1.0]
    };
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];

    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqualToString:@"q"]) {
            [self dismissAction:nil];
            return nil;
        }
        return event;
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    printf("%s\n", [self.result UTF8String]);
    fflush(stdout);
    [NSApp terminate:nil];
}

- (void)dismissAction:(id)sender {
    self.result = @"Dismiss";
    [self.window close];
}

- (void)openAction:(id)sender {
    NSURL *url = [NSURL URLWithString:self.urlText];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    self.result = @"Open in Airflow";
}

- (NSTextField *)labelWithFrame:(NSRect)frame
                           text:(NSString *)text
                           font:(NSFont *)font
                          color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text ?: @""];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setFont:font];
    [label setTextColor:color];
    [label setLineBreakMode:NSLineBreakByWordWrapping];
    [label setUsesSingleLineMode:NO];
    return label;
}

- (void)buildWindow {
    NSDictionary<NSString *, NSColor *> *theme = [self theme];
    NSRect rect = NSMakeRect(0, 0, 640, 320);
    self.window = [[NSWindow alloc] initWithContentRect:rect
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:@"Dagsy: Your DAG Watcher"];
    [self.window setReleasedWhenClosed:NO];
    [self.window setLevel:NSFloatingWindowLevel];
    [self.window setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary)];
    [self.window setDelegate:self];
    [[self.window standardWindowButton:NSWindowZoomButton] setHidden:YES];

    NSView *content = [[NSView alloc] initWithFrame:rect];
    [self.window setContentView:content];

    NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(14, 14, 612, 292)];
    [card setWantsLayer:YES];
    card.layer.backgroundColor = theme[@"surface"].CGColor;
    card.layer.borderColor = theme[@"border"].CGColor;
    card.layer.borderWidth = 1.0;
    card.layer.cornerRadius = 14.0;
    [content addSubview:card];

    NSView *accent = [[NSView alloc] initWithFrame:NSMakeRect(0, 286, 612, 6)];
    [accent setWantsLayer:YES];
    accent.layer.backgroundColor = theme[@"accent"].CGColor;
    [card addSubview:accent];

    NSTextField *title = [self labelWithFrame:NSMakeRect(22, 236, 560, 28)
                                         text:self.titleText
                                         font:[NSFont boldSystemFontOfSize:20]
                                        color:[NSColor colorWithCalibratedWhite:0.08 alpha:1.0]];
    [card addSubview:title];

    NSString *subtitleText = [[self.kind lowercaseString] isEqualToString:@"success"] ? @"Airflow Success" :
                             ([[self.kind lowercaseString] isEqualToString:@"failure"] ? @"Airflow Failure" : @"Airflow Update");
    NSTextField *subtitle = [self labelWithFrame:NSMakeRect(22, 214, 560, 20)
                                            text:subtitleText
                                            font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
                                           color:[NSColor colorWithCalibratedWhite:0.36 alpha:1.0]];
    [card addSubview:subtitle];

    NSTextField *message = [self labelWithFrame:NSMakeRect(22, 78, 568, 126)
                                           text:self.messageText
                                           font:[NSFont systemFontOfSize:13]
                                          color:[NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
    [card addSubview:message];

    NSButton *dismiss = [[NSButton alloc] initWithFrame:NSMakeRect(492, 24, 96, 34)];
    [dismiss setTitle:@"Dismiss"];
    [dismiss setBezelStyle:NSBezelStyleRounded];
    [dismiss setTarget:self];
    [dismiss setAction:@selector(dismissAction:)];
    [card addSubview:dismiss];

    NSButton *open = [[NSButton alloc] initWithFrame:NSMakeRect(344, 24, 136, 34)];
    [open setTitle:@"Open in Airflow"];
    [open setBordered:NO];
    [open setTarget:self];
    [open setAction:@selector(openAction:)];
    [open setWantsLayer:YES];
    open.layer.backgroundColor = theme[@"button"].CGColor;
    open.layer.cornerRadius = 8.0;
    [open setContentTintColor:[NSColor whiteColor]];
    [card addSubview:open];

    NSScreen *screen = [NSScreen mainScreen];
    if (screen != nil) {
        NSRect visible = [screen visibleFrame];
        CGFloat x = visible.origin.x + floor((visible.size.width - NSWidth(rect)) / 2.0);
        CGFloat y = visible.origin.y + floor((visible.size.height - NSHeight(rect)) / 2.0);
        [self.window setFrameOrigin:NSMakePoint(x, y)];
    }
}

@end

static NSString *valueForFlag(NSArray<NSString *> *arguments, NSString *flag, NSString *fallback) {
    NSUInteger index = [arguments indexOfObject:flag];
    if (index != NSNotFound && index + 1 < [arguments count]) {
        return arguments[index + 1];
    }
    return fallback;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        NSString *title = valueForFlag(arguments, @"--title", @"Dagsy: Your DAG Watcher");
        NSString *message = valueForFlag(arguments, @"--message", @"");
        NSString *url = valueForFlag(arguments, @"--url", @"http://localhost:8080");
        NSString *kind = valueForFlag(arguments, @"--kind", @"generic");

        NSApplication *app = [NSApplication sharedApplication];
        PopupController *delegate = [[PopupController alloc] initWithTitle:title message:message url:url kind:kind];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
