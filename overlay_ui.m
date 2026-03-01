#import <AppKit/AppKit.h>
#include <string.h>

// MARK: - WaveformView

@interface WaveformView : NSView
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic, assign) BOOL animating;
@end

@implementation WaveformView {
    CGFloat _barHeights[12];
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _animating = NO;
        for (int i = 0; i < 12; i++) {
            _barHeights[i] = 0.2;
        }
    }
    return self;
}

- (void)startAnimating {
    if (_animating) return;
    _animating = YES;
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                      target:self
                                                    selector:@selector(tick)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)stopAnimating {
    _animating = NO;
    [_animationTimer invalidate];
    _animationTimer = nil;
    for (int i = 0; i < 12; i++) {
        _barHeights[i] = 0.2;
    }
    [self setNeedsDisplay:YES];
}

- (void)tick {
    for (int i = 0; i < 12; i++) {
        CGFloat target = 0.2 + ((CGFloat)arc4random_uniform(80)) / 100.0;
        _barHeights[i] += (target - _barHeights[i]) * 0.3;
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    CGFloat barWidth = 3.0;
    CGFloat gap = 3.0;
    CGFloat totalWidth = 12 * barWidth + 11 * gap;
    CGFloat startX = (bounds.size.width - totalWidth) / 2.0;
    CGFloat maxHeight = bounds.size.height * 0.8;
    CGFloat centerY = bounds.size.height / 2.0;

    [[NSColor colorWithWhite:1.0 alpha:0.7] setFill];

    for (int i = 0; i < 12; i++) {
        CGFloat h = maxHeight * _barHeights[i];
        CGFloat x = startX + i * (barWidth + gap);
        CGFloat y = centerY - h / 2.0;
        NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, barWidth, h)
                                                            xRadius:1.5
                                                            yRadius:1.5];
        [bar fill];
    }
}

@end

// MARK: - Overlay globals

static NSPanel *_overlayPanel = nil;
static NSTextField *_transcriptionField = nil;
static NSTextField *_statusField = nil;
static WaveformView *_waveformView = nil;
static BOOL _overlayVisible = NO;

// MARK: - Public functions

void initNSApplication(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
}

void setupOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat panelWidth = 600;
        CGFloat panelHeight = 120;

        // Position at bottom center of main screen
        NSScreen *screen = [NSScreen mainScreen];
        NSRect screenFrame = screen.visibleFrame;
        CGFloat x = screenFrame.origin.x + (screenFrame.size.width - panelWidth) / 2.0;
        CGFloat y = screenFrame.origin.y + 40; // 40pt from bottom

        NSRect panelRect = NSMakeRect(x, y, panelWidth, panelHeight);

        _overlayPanel = [[NSPanel alloc] initWithContentRect:panelRect
                                                   styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

        [_overlayPanel setLevel:NSFloatingWindowLevel];
        [_overlayPanel setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                             NSWindowCollectionBehaviorStationary];
        [_overlayPanel setOpaque:NO];
        [_overlayPanel setBackgroundColor:[NSColor clearColor]];
        [_overlayPanel setHasShadow:YES];
        [_overlayPanel setHidesOnDeactivate:NO];

        // Content view with rounded dark background
        NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, panelWidth, panelHeight)];
        contentView.wantsLayer = YES;
        contentView.layer.backgroundColor = [NSColor colorWithWhite:0.1 alpha:0.85].CGColor;
        contentView.layer.cornerRadius = 16.0;
        contentView.layer.masksToBounds = YES;
        [_overlayPanel setContentView:contentView];

        // Transcription text field (centered, takes most of the width)
        _transcriptionField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, panelWidth - 120, 50)];
        [_transcriptionField setBezeled:NO];
        [_transcriptionField setDrawsBackground:NO];
        [_transcriptionField setEditable:NO];
        [_transcriptionField setSelectable:NO];
        [_transcriptionField setTextColor:[NSColor whiteColor]];
        [_transcriptionField setFont:[NSFont systemFontOfSize:16.0 weight:NSFontWeightMedium]];
        [_transcriptionField setStringValue:@"Listening..."];
        [_transcriptionField setAlignment:NSTextAlignmentLeft];
        [_transcriptionField setLineBreakMode:NSLineBreakByTruncatingTail];
        [_transcriptionField setCell:_transcriptionField.cell];
        [contentView addSubview:_transcriptionField];

        // Status label
        _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 15, 200, 20)];
        [_statusField setBezeled:NO];
        [_statusField setDrawsBackground:NO];
        [_statusField setEditable:NO];
        [_statusField setSelectable:NO];
        [_statusField setTextColor:[NSColor colorWithWhite:0.6 alpha:1.0]];
        [_statusField setFont:[NSFont systemFontOfSize:12.0]];
        [_statusField setStringValue:@"Dictating..."];
        [contentView addSubview:_statusField];

        // Waveform view (right side)
        _waveformView = [[WaveformView alloc] initWithFrame:NSMakeRect(panelWidth - 90, 20, 70, 80)];
        [contentView addSubview:_waveformView];

        // Start hidden
        [_overlayPanel orderOut:nil];
        _overlayVisible = NO;
    });
}

void showOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_transcriptionField setStringValue:@"Listening..."];
        [_statusField setStringValue:@"Dictating..."];
        [_overlayPanel orderFrontRegardless];
        [_waveformView startAnimating];
        _overlayVisible = YES;
    });
}

void hideOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_waveformView stopAnimating];
        [_overlayPanel orderOut:nil];
        _overlayVisible = NO;
    });
}

int isOverlayVisible(void) {
    return _overlayVisible ? 1 : 0;
}

// Returns a strdup'd C string — caller must free().
// Called from the main thread (event tap callback runs on main CFRunLoop).
char *getTranscriptionText(void) {
    NSString *str = [_transcriptionField stringValue];
    return strdup([str UTF8String]);
}

void updateTranscriptionText(const char *text) {
    NSString *str = [NSString stringWithUTF8String:text];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_transcriptionField setStringValue:str];
    });
}

void updateStatusLabel(const char *text) {
    NSString *str = [NSString stringWithUTF8String:text];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_statusField setStringValue:str];
    });
}

void stopWaveform(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_waveformView stopAnimating];
    });
}
