#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>

#import "authenticator/BaseAuthenticator.h"
#import "customcontrols/ControlButton.h"
#import "customcontrols/ControlDrawer.h"
#import "customcontrols/ControlSubButton.h"
#import "customcontrols/CustomControlsUtils.h"

#import "input/ControllerInput.h"
#import "input/GyroInput.h"
#import "input/KeyboardInput.h"

#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceUtils.h"
#import "PLProfiles.h"
#import "SurfaceViewController.h"
#import "TrackedTextField.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"

#include "glfw_keycodes.h"
#include "utils.h"

#include <dlfcn.h>

int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);
#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT        6

static int currentHotbarSlot = -1;
static GameSurfaceView* pojavWindow;
static NSNotificationName const FluidButtonSlidePreferenceDidChangeNotification =
    @"FluidButtonSlidePreferenceDidChangeNotification";

@interface SurfaceViewController ()<UITextFieldDelegate, UIGestureRecognizerDelegate> {
}

@property(nonatomic) NSDictionary* metadata;

@property(nonatomic) TrackedTextField *inputTextField;
@property(nonatomic) NSMutableArray* swipeableButtons;
@property(nonatomic) ControlButton* swipingButton;
@property(nonatomic) UILongPressGestureRecognizer *fluidButtonPanGesture;
@property(nonatomic) NSMutableArray<ControlButton *> *fluidActiveButtons;
@property(nonatomic) BOOL fluidMovementCaptured;
@property(nonatomic) CGPoint fluidGestureOrigin;
@property(nonatomic) NSMutableDictionary<NSString *, UIView *> *diagonalIndicators;
@property(nonatomic) CAShapeLayer *directionRingLayer;
@property(nonatomic) UITouch *primaryTouch, *hotbarTouch;

@property(nonatomic) UILongPressGestureRecognizer* longPressGesture, *longPressTwoGesture;
@property(nonatomic) UITapGestureRecognizer *tapGesture, *doubleTapGesture;

@property(nonatomic) id mouseConnectCallback, mouseDisconnectCallback;
@property(nonatomic) id controllerConnectCallback, controllerDisconnectCallback;

@property(nonatomic) CGFloat screenScale;
@property(nonatomic) CGFloat mouseSpeed;
@property(nonatomic) CGRect clickRange;
@property(nonatomic) BOOL isMacCatalystApp, shouldHideControlsFromRecording,
    shouldTriggerClick, shouldTriggerHaptic, slideableHotbar, toggleHidden;

@property(nonatomic) BOOL enableMouseGestures, enableHotbarGestures;

@property(nonatomic) CGSize lastLaidOutGameSize;

@property(nonatomic) UIImpactFeedbackGenerator *lightHaptic;
@property(nonatomic) UIImpactFeedbackGenerator *mediumHaptic;

@end

@implementation SurfaceViewController

- (instancetype)initWithMetadata:(NSDictionary *)metadata {
    self = [super init];
    self.metadata = metadata;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    isControlModifiable = NO;
    self.isMacCatalystApp = NSProcessInfo.processInfo.isMacCatalystApp;
    // Load MetalHUD library
    dlopen("/usr/lib/libMTLHud.dylib", 0);

    self.lightHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyleLight)];
    self.mediumHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyleMedium)];

    //setPrefBool(@"internal.internal_launch_on_boot", NO);

    UIApplication.sharedApplication.idleTimerDisabled = YES;
    BOOL isTVOS = realUIIdiom == UIUserInterfaceIdiomTV;
    if (!isTVOS) {
        [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }

    // Perform Gamepad joystick ticking, while also controlling frame rate?
    id tickInput = ^{
        [GyroInput tick];
        [ControllerInput tick];
    };
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:tickInput selector:@selector(invoke)];
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        if(getPrefBool(@"video.max_framerate")) {
            displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);
        } else {
            displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        }
    }
    [displayLink addToRunLoop:NSRunLoop.currentRunLoop forMode:NSRunLoopCommonModes];

    CGFloat screenScale = UIScreen.mainScreen.scale;

    [self updateSavedResolution];

    self.rootView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width + 30.0, self.view.frame.size.height)];
    self.rootView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.rootView];

    self.ctrlView = [[ControlLayout alloc] initWithFrame:getSafeArea(self.view.frame)];

    [self performSelector:@selector(initCategory_Navigation)];
    
    self.surfaceView = [[GameSurfaceView alloc] initWithFrame:self.view.frame];
    self.surfaceView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.surfaceView.layer.contentsScale = screenScale * resolutionScale;
    self.surfaceView.layer.magnificationFilter = self.surfaceView.layer.minificationFilter = kCAFilterNearest;
    self.surfaceView.multipleTouchEnabled = YES;
    pojavWindow = self.surfaceView;

    self.touchView = [[UIView alloc] initWithFrame:self.view.frame];
    self.touchView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.touchView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:1];
    self.touchView.multipleTouchEnabled = YES;
    [self.touchView addSubview:self.surfaceView];

    [self.rootView addSubview:self.touchView];
    [self.rootView addSubview:self.ctrlView];

    self.fluidActiveButtons = [NSMutableArray array];
    self.diagonalIndicators = [NSMutableDictionary dictionary];
    [self updateFluidButtonSlideState];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(fluidButtonSlidePreferenceDidChange:)
               name:FluidButtonSlidePreferenceDidChangeNotification
             object:nil];

    [self performSelector:@selector(setupCategory_Navigation)];

    
    UIHoverGestureRecognizer *hoverGesture = [[NSClassFromString(@"UIHoverGestureRecognizer") alloc] initWithTarget:self action:@selector(surfaceOnHover:)];
    [self.touchView addGestureRecognizer:hoverGesture];

    self.tapGesture = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(surfaceOnClick:)];
    self.tapGesture.allowedTouchTypes = @[@(UITouchTypeDirect)];
    self.tapGesture.delegate = self;
    self.tapGesture.numberOfTapsRequired = 1;
    self.tapGesture.numberOfTouchesRequired = 1;
    self.tapGesture.cancelsTouchesInView = NO;
    [self.touchView addGestureRecognizer:self.tapGesture];

    self.doubleTapGesture = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(surfaceOnDoubleClick:)];
    self.doubleTapGesture.allowedTouchTypes = @[@(UITouchTypeDirect)];
    self.doubleTapGesture.delegate = self;
    self.doubleTapGesture.numberOfTapsRequired = 2;
    self.doubleTapGesture.numberOfTouchesRequired = 1;
    self.doubleTapGesture.cancelsTouchesInView = NO;
    [self.touchView addGestureRecognizer:self.doubleTapGesture];

    self.longPressGesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(surfaceOnLongpress:)];
    self.longPressGesture.allowedTouchTypes = @[@(UITouchTypeDirect)];
    self.longPressGesture.cancelsTouchesInView = NO;
    self.longPressGesture.delegate = self;
    [self.touchView addGestureRecognizer:self.longPressGesture];
    
    self.longPressTwoGesture = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(keyboardGesture:)];
    self.longPressTwoGesture.numberOfTouchesRequired = 2;
    self.longPressTwoGesture.allowedTouchTypes = @[@(UITouchTypeDirect)];
    self.longPressTwoGesture.cancelsTouchesInView = NO;
    self.longPressTwoGesture.delegate = self;
    [self.touchView addGestureRecognizer:self.longPressTwoGesture];

    self.scrollPanGesture = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(surfaceOnTouchesScroll:)];
    self.scrollPanGesture.allowedTouchTypes = @[@(UITouchTypeDirect)];
    self.scrollPanGesture.delegate = self;
    self.scrollPanGesture.minimumNumberOfTouches = 2;
    self.scrollPanGesture.maximumNumberOfTouches = 2;
    [self.touchView addGestureRecognizer:self.scrollPanGesture];

    // Virtual mouse
    virtualMouseEnabled = getPrefBool(@"control.virtmouse_enable");
    virtualMouseFrame = CGRectMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2, 18, 27);
    self.mousePointerView = [[UIImageView alloc] initWithFrame:virtualMouseFrame];
    self.mousePointerView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin |UIViewAutoresizingFlexibleBottomMargin;
    self.mousePointerView.hidden = !virtualMouseEnabled;
    self.mousePointerView.image = [UIImage imageNamed:@"MousePointer"];
    self.mousePointerView.userInteractionEnabled = NO;
    [self.touchView addSubview:self.mousePointerView];

    self.inputTextField = [[TrackedTextField alloc] initWithFrame:CGRectMake(0, -32.0, self.view.frame.size.width, 30.0)];
    self.inputTextField.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.inputTextField.delegate = self;
    self.inputTextField.font = [UIFont fontWithName:@"Menlo-Regular" size:20];
    self.inputTextField.clearsOnBeginEditing = YES;
    self.inputTextField.textAlignment = NSTextAlignmentCenter;
    self.inputTextField.sendChar = ^(jchar keychar){
        CallbackBridge_nativeSendChar(keychar);
    };
    self.inputTextField.sendCharMods = ^(jchar keychar, int mods){
        CallbackBridge_nativeSendCharMods(keychar, mods);
    };
    self.inputTextField.sendKey = ^(int key, int scancode, int action, int mods) {
        CallbackBridge_nativeSendKey(key, scancode, action, mods);
    };

    self.swipeableButtons = [[NSMutableArray alloc] init];

    [KeyboardInput initKeycodeTable];
    self.mouseConnectCallback = [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSLog(@"Input: Mouse connected!");
        GCMouse* mouse = note.object;
        [self registerMouseCallbacks:mouse];
        self.mousePointerView.hidden = isGrabbing || !virtualMouseEnabled;
        [self setNeedsUpdateOfPrefersPointerLocked];
    }];
    self.mouseDisconnectCallback = [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSLog(@"Input: Mouse disconnected!");
        GCMouse* mouse = note.object;
        mouse.mouseInput.mouseMovedHandler = nil;
        mouse.mouseInput.leftButton.pressedChangedHandler = nil;
        mouse.mouseInput.middleButton.pressedChangedHandler = nil;
        mouse.mouseInput.rightButton.pressedChangedHandler = nil;
        [mouse.mouseInput.auxiliaryButtons makeObjectsPerformSelector:@selector(setPressedChangedHandler:) withObject:nil];
        [self setNeedsUpdateOfPrefersPointerLocked];
        if (getPrefBool(@"controll.hardware_hide")) {
            self.ctrlView.hidden = NO;
        }
    }];
    if (GCMouse.current != nil) {
        [self registerMouseCallbacks:GCMouse.current];
    }
    

    // TODO: deal with multiple controllers by letting users decide which one to use?
    self.controllerConnectCallback = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSLog(@"Input: Controller connected!");
        GCController* controller = note.object;
        [ControllerInput initKeycodeTable];
        [ControllerInput registerControllerCallbacks:controller];
        self.mousePointerView.hidden = isGrabbing;
        virtualMouseEnabled = YES;
        if (getPrefBool(@"control.hardware_hide")) {
            self.ctrlView.hidden = YES;
        }
    }];
    self.controllerDisconnectCallback = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSLog(@"Input: Controller disconnected!");
        GCController* controller = note.object;
        [ControllerInput unregisterControllerCallbacks:controller];
        if (getPrefBool(@"control.hardware_hide")) {
            self.ctrlView.hidden = NO;
        }
    }];
    if (GCController.controllers.count == 1) {
        [ControllerInput initKeycodeTable];
        [ControllerInput registerControllerCallbacks:GCController.controllers.firstObject];
    }

    [self.rootView addSubview:self.inputTextField];

    [self performSelector:@selector(initCategory_LogView)];

    // [self setPreferredFramesPerSecond:1000];
    [self updateJetsamControl];
    [self updatePreferenceChanges];
    [self loadCustomControls];

    if (UIApplication.sharedApplication.connectedScenes.count > 1 &&
      getPrefBool(@"video.fullscreen_airplay")) {
        [self switchToExternalDisplay];
    }

    [self launchMinecraft];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait |
        UIInterfaceOrientationMaskLandscapeLeft |
        UIInterfaceOrientationMaskLandscapeRight;
}

// iOS 14 can finish rotating the UIWindow before the transition animation
// block receives the controller's new frame.  Always derive the game canvas
// from the final view bounds and update every layer from one place.
- (void)synchronizeGameLayoutForSize:(CGSize)size {
    if (size.width <= 0.0 || size.height <= 0.0 || !self.rootView) return;

    CGRect gameBounds = CGRectMake(0.0, 0.0, size.width, size.height);
    self.rootView.bounds = CGRectMake(0.0, 0.0, size.width + 30.0, size.height);
    self.touchView.frame = gameBounds;
    self.surfaceView.frame = self.touchView.bounds;
    self.inputTextField.frame = CGRectMake(0.0, -32.0, size.width, 30.0);
    self.ctrlView.frame = getSafeArea(gameBounds);

    [self viewWillTransitionToSize_Navigation:gameBounds];
    for (UIView *view in self.ctrlView.subviews) {
        if ([view isKindOfClass:ControlButton.class]) {
            [(ControlButton *)view update];
        }
    }

    if (!CGSizeEqualToSize(self.lastLaidOutGameSize, size)) {
        self.lastLaidOutGameSize = size;
        [self updateSavedResolution];
        [GyroInput updateOrientation];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self synchronizeGameLayoutForSize:self.view.bounds.size];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self setNeedsUpdateOfPrefersPointerLocked];
}

- (void)updateAudioSettings {
    NSError *sessionError = nil;
    AVAudioSessionCategory category;
    AVAudioSessionCategoryOptions options = 0;
    if(getPrefBool(@"video.allow_microphone")) {
        category = AVAudioSessionCategoryPlayAndRecord;
        options |= AVAudioSessionCategoryOptionAllowAirPlay | AVAudioSessionCategoryOptionAllowBluetoothA2DP | AVAudioSessionCategoryOptionDefaultToSpeaker;
    } else if(getPrefBool(@"video.silence_with_switch")) {
        category = AVAudioSessionCategorySoloAmbient;
    } else {
        category = AVAudioSessionCategoryPlayback;
    }
    if(!getPrefBool(@"video.silence_other_audio")) {
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:category withOptions:options error:&sessionError];
    [session setActive:YES error:&sessionError];
}

- (void)updateJetsamControl {
    if (!getEntitlementValue(@"com.apple.private.memorystatus")) {
        return;
    }
    // More 1024MB is necessary for other memory regions (native, Java GC, etc.)
    int limit = getPrefInt(@"java.allocated_memory") + 1024;
    if (memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT, getpid(), limit, NULL, 0) == -1) {
        NSLog(@"Failed to set Jetsam task limit: error: %s", strerror(errno));
    } else {
        NSLog(@"Successfully set Jetsam task limit");
    }
}

- (void)updatePreferenceChanges {
    // Update UITextField auto correction
    if (getPrefBool(@"debug.debug_auto_correction")) {
        self.inputTextField.autocorrectionType = UITextAutocorrectionTypeDefault;
    } else {
        self.inputTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    }

    BOOL gyroEnabled = getPrefBool(@"control.gyroscope_enable");
    BOOL gyroInvertX = getPrefBool(@"control.gyroscope_invert_x_axis");
    int gyroSensitivity = getPrefInt(@"control.gyroscope_sensitivity");
    [GyroInput updateSensitivity:gyroEnabled?gyroSensitivity:0 invertXAxis:gyroInvertX];

    self.mouseSpeed = getPrefFloat(@"control.mouse_speed") / 100.0;

    virtualMouseEnabled = getPrefBool(@"control.virtmouse_enable");
    self.mousePointerView.hidden = isGrabbing || !virtualMouseEnabled;

    // Update virtual mouse scale
    CGFloat mouseScale = getPrefFloat(@"control.mouse_scale") / 100.0;
    virtualMouseFrame = CGRectMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2, 18.0 * mouseScale, 27 * mouseScale);
    self.mousePointerView.frame = virtualMouseFrame;

    self.shouldHideControlsFromRecording = getPrefFloat(@"control.recording_hide");
    [self.ctrlView hideViewFromCapture:self.shouldHideControlsFromRecording];
    self.ctrlView.frame = getSafeArea(self.view.frame);

    // Update gestures state
    self.slideableHotbar = getPrefBool(@"control.slideable_hotbar");
    self.enableMouseGestures = getPrefBool(@"control.gesture_mouse");
    self.enableHotbarGestures = getPrefBool(@"control.gesture_hotbar");
    self.shouldTriggerHaptic = !getPrefBool(@"control.disable_haptics");

    self.scrollPanGesture.enabled = self.enableMouseGestures;
    self.doubleTapGesture.enabled = self.enableHotbarGestures;
    self.longPressGesture.minimumPressDuration = getPrefFloat(@"control.press_duration") / 1000.0;

    // Update audio settings
    [self updateAudioSettings];
    // Update resolution
    [self updateSavedResolution];
    // Update performance HUD visibility
    if (@available(iOS 16, tvOS 16, *)) {
        if ([self.surfaceView.layer isKindOfClass:CAMetalLayer.class]) {
            BOOL perfHUDEnabled = getPrefBool(@"video.performance_hud");
            ((CAMetalLayer *)self.surfaceView.layer).developerHUDProperties = perfHUDEnabled ? @{@"mode": @"default"} : nil;
        }
    }
    // Update pointer lock state
    [self setNeedsUpdateOfPrefersPointerLocked];
}

- (void)updateSavedResolution {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes.allObjects) {
        self.screenScale = scene.screen.scale;
        if (scene.session.role != UIWindowSceneSessionRoleApplication) {
            break;
        }
    }

    if (self.surfaceView.superview != nil) {
        self.surfaceView.frame = self.surfaceView.superview.frame;
    }

    resolutionScale = getPrefFloat(@"video.resolution") / 100.0;
    self.surfaceView.layer.contentsScale = self.screenScale * resolutionScale;

    physicalWidth = roundf(self.surfaceView.frame.size.width * self.screenScale);
    physicalHeight = roundf(self.surfaceView.frame.size.height * self.screenScale);
    windowWidth = roundf(physicalWidth * resolutionScale);
    windowHeight = roundf(physicalHeight * resolutionScale);
    // Resolution should not be odd
    if ((windowWidth % 2) != 0) {
        --windowWidth;
    }
    if ((windowHeight % 2) != 0) {
        --windowHeight;
    }
    CallbackBridge_nativeSendScreenSize(windowWidth, windowHeight);
}

- (void)updateControlHiddenState:(BOOL)hide {
    if (hide) {
        [self setVisibleDiagonalIndicator:nil];
        self.directionRingLayer.opacity = 0;
    }
    for (UIView *view in self.ctrlView.subviews) {
        if (![view isKindOfClass:ControlButton.class]) continue;
        ControlButton *button = (ControlButton *)view;
        if (!button.canBeHidden) continue;
        BOOL hidden = hide || !(
            (isGrabbing && [button.properties[@"displayInGame"] boolValue]) ||
            (!isGrabbing && [button.properties[@"displayInMenu"] boolValue]));
        if (!hidden && ![button isKindOfClass:ControlSubButton.class]) {
            button.hidden = hidden;
            if ([button isKindOfClass:ControlDrawer.class]) {
                [(ControlDrawer *)button restoreButtonVisibility];
            }
        } else if (hidden) {
            button.hidden = hidden;
        }
    }
}

- (void)updateGrabState {
    // Update cursor position
    if (isGrabbing == JNI_TRUE) {
        CGFloat screenScale = self.surfaceView.layer.contentsScale;
        CallbackBridge_nativeSendCursorPos(ACTION_DOWN, lastVirtualMousePoint.x * screenScale, lastVirtualMousePoint.y * screenScale);
        virtualMouseFrame.origin.x = self.view.frame.size.width / 2;
        virtualMouseFrame.origin.y = self.view.frame.size.height / 2;
        self.mousePointerView.frame = virtualMouseFrame;
    }
    self.scrollPanGesture.enabled = !isGrabbing;
    self.mousePointerView.hidden = isGrabbing || !virtualMouseEnabled;
    [self setNeedsUpdateOfPrefersPointerLocked];

    // Update buttons visibility
    [self updateControlHiddenState:NO];
}

- (void)launchMinecraft {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int minVersion = [self.metadata[@"javaVersion"][@"majorVersion"] intValue];
        if (minVersion == 0) {
            minVersion = [self.metadata[@"javaVersion"][@"version"] intValue];
        }
        NSString *accountStorageKey =
            [BaseAuthenticator storageKeyForAuthData:BaseAuthenticator.current.authData];
        launchJVM(
            accountStorageKey,
            self.metadata,
            windowWidth, windowHeight,
            minVersion
        );
    });
}

- (void)updateFluidButtonSlideState {
    BOOL enabled = getPrefBool(@"control.fluid_button_slide");
    if (enabled && !self.fluidButtonPanGesture) {
        self.fluidButtonPanGesture = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleFluidButtonPan:)];
        self.fluidButtonPanGesture.minimumPressDuration = 0;
        self.fluidButtonPanGesture.allowableMovement = CGFLOAT_MAX;
        self.fluidButtonPanGesture.allowedTouchTypes = @[@(UITouchTypeDirect)];
        self.fluidButtonPanGesture.numberOfTouchesRequired = 1;
        self.fluidButtonPanGesture.cancelsTouchesInView = NO;
        self.fluidButtonPanGesture.delegate = self;
        [self.rootView addGestureRecognizer:self.fluidButtonPanGesture];
    }
    self.fluidButtonPanGesture.enabled = enabled;
    if (!enabled) {
        [self applyFluidButtons:@[]];
        self.fluidMovementCaptured = NO;
        [self setVisibleDiagonalIndicator:nil];
        self.directionRingLayer.opacity = 0;
    }
}

- (void)fluidButtonSlidePreferenceDidChange:(NSNotification *)notification {
    [self updateFluidButtonSlideState];
    [self loadCustomControls];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadCustomControls {
    self.edgeGesture.enabled = YES;
    [self.swipeableButtons removeAllObjects];
    for (UIView *indicator in self.diagonalIndicators.allValues) {
        [indicator removeFromSuperview];
    }
    [self.diagonalIndicators removeAllObjects];
    [self.directionRingLayer removeFromSuperlayer];
    self.directionRingLayer = nil;
    NSString *controlFile = [PLProfiles resolveKeyForCurrentProfile:@"defaultTouchCtrl"];
    [self.ctrlView loadControlFile:controlFile];

    ControlButton *menuButton;
    for (UIView *view in self.ctrlView.subviews) {
        if (![view isKindOfClass:ControlButton.class]) continue;
        ControlButton *button = (ControlButton *)view;
        BOOL isSwipeable = [button.properties[@"isSwipeable"] boolValue];

        button.canBeHidden = YES;
        BOOL isMenuButton = NO;
        for (int i = 0; i < 4; i++) {
            int keycodeInt = [button.properties[@"keycodes"][i] intValue];
            button.canBeHidden &= keycodeInt != SPECIALBTN_TOGGLECTRL && keycodeInt != SPECIALBTN_VIRTUALMOUSE;
            if (keycodeInt == SPECIALBTN_MENU) {
                menuButton = button;
            }
        }

        BOOL fluidMovementButton =
            getPrefBool(@"control.fluid_button_slide") &&
            [self isFluidMovementButton:button];
        if (!fluidMovementButton) {
            [button addTarget:self action:@selector(executebtn_down:) forControlEvents:UIControlEventTouchDown];
            [button addTarget:self action:@selector(executebtn_up_inside:) forControlEvents:UIControlEventTouchUpInside];
            [button addTarget:self action:@selector(executebtn_up_outside:) forControlEvents:UIControlEventTouchUpOutside];
        }

        BOOL fluidEligible = getPrefBool(@"control.fluid_button_slide") &&
            ![button.properties[@"isToggle"] boolValue] &&
            ![button isKindOfClass:ControlDrawer.class];
        if (isSwipeable && !fluidEligible) {
            UIPanGestureRecognizer *panRecognizerButton = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(executebtn_swipe:)];
            panRecognizerButton.delegate = self;
            [button addGestureRecognizer:panRecognizerButton];
        }
        if (isSwipeable || fluidEligible) {
            [self.swipeableButtons addObject:button];
        }
    }

    [self updateControlHiddenState:self.toggleHidden];

    if (menuButton) {
        NSMutableArray *items = [NSMutableArray new];
        for (int i = 0; i < self.menuArray.count; i++) {
            UIAction *item = [UIAction actionWithTitle:localize(self.menuArray[i], nil) image:nil identifier:nil
                handler:^(id action) {[self didSelectMenuItem:i];}];
            [items addObject:item];
        }
        menuButton.menu = [UIMenu menuWithTitle:@"" image:nil identifier:nil
            options:UIMenuOptionsDisplayInline children:items];
        menuButton.showsMenuAsPrimaryAction = YES;
        self.edgeGesture.enabled = NO;
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self synchronizeGameLayoutForSize:size];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        // On iOS 14 the final safe-area and UIWindow bounds are only reliable
        // after the transition completes, so perform one final synchronization.
        [self synchronizeGameLayoutForSize:self.view.bounds.size];
        virtualMouseFrame = self.mousePointerView.frame;
    }];
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - Input: send touch utilities

- (BOOL)isTouchInactive:(UITouch *)touch {
    return touch == nil || touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled;
}

- (void)sendTouchPoint:(CGPoint)location withEvent:(int)event
{
    CGFloat screenScale = self.screenScale;
    if (!isGrabbing) {
        screenScale *= resolutionScale;
        if (virtualMouseEnabled) {
            if (event == ACTION_MOVE) {
                virtualMouseFrame.origin.x += (location.x - lastVirtualMousePoint.x) * self.mouseSpeed;
                virtualMouseFrame.origin.y += (location.y - lastVirtualMousePoint.y) * self.mouseSpeed;
            } else if (event == ACTION_MOVE_MOTION) {
                event = ACTION_MOVE;
                virtualMouseFrame.origin.x += location.x * self.mouseSpeed;
                virtualMouseFrame.origin.y += location.y * self.mouseSpeed;
            }
            virtualMouseFrame.origin.x = clamp(virtualMouseFrame.origin.x, 0, self.surfaceView.frame.size.width);
            virtualMouseFrame.origin.y = clamp(virtualMouseFrame.origin.y, 0, self.surfaceView.frame.size.height);
            lastVirtualMousePoint = location;
            self.mousePointerView.frame = virtualMouseFrame;
            CallbackBridge_nativeSendCursorPos(event, virtualMouseFrame.origin.x * screenScale, virtualMouseFrame.origin.y * screenScale);
            return;
        }
        lastVirtualMousePoint = location;
    }
    CallbackBridge_nativeSendCursorPos(event, location.x * screenScale, location.y * screenScale);
}

#pragma mark - Input: on-surface functions

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)keyboardGesture:(UIGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        if (self.inputTextField.isFirstResponder) {
            [self.inputTextField resignFirstResponder];
            self.inputTextField.alpha = 1.0f;
        } else {
            [self.inputTextField becomeFirstResponder];
            // Insert an undeletable space
            self.inputTextField.text = @" ";
        }
    }
}

- (void)sendTouchEvent:(UITouch *)touchEvent withUIEvent:(UIEvent *)uievent withEvent:(int)event
{
    CGPoint locationInView = [touchEvent locationInView:self.rootView];

    //if (touchEvent.view == self.surfaceView) {
        switch (event) {
            case ACTION_DOWN:
                self.clickRange = CGRectMake(locationInView.x - 2, locationInView.y - 2, 5, 5);
                self.shouldTriggerClick = YES;
                break;

            case ACTION_MOVE:
                if (self.shouldTriggerClick && !CGRectContainsPoint(self.clickRange, locationInView)) {
                    self.shouldTriggerClick = NO;
                }
                break;
        }

        if (touchEvent == self.hotbarTouch && self.slideableHotbar && ![self isTouchInactive:self.hotbarTouch]) {
            CGFloat screenScale = [[UIScreen mainScreen] scale];
            int slot = self.enableHotbarGestures ?
            callback_SurfaceViewController_touchHotbar(locationInView.x * screenScale, locationInView.y * screenScale) : -1;
            if (slot != -1 && currentHotbarSlot != slot && (event == ACTION_DOWN || currentHotbarSlot != -1)) {
                currentHotbarSlot = slot;
                CallbackBridge_nativeSendKey(slot, 0, 1, 0);
                CallbackBridge_nativeSendKey(slot, 0, 0, 0);
                return;
            } /* else if ((event == ACTION_MOVE || event == ACTION_UP) && slot == -1 && currentHotbarSlot != -1) {
                return;
            } */
            
            if (event == ACTION_DOWN && slot == -1) {
                currentHotbarSlot = -1;
            }
            /*
            if (currentHotbarSlot != -1) {
                return;
            }
            */
            return;
        }

        if (touchEvent == self.primaryTouch) {
            if ([self isTouchInactive:self.primaryTouch]) return; // FIXME: should be? ACTION_UP will never be sent
            if (event == ACTION_MOVE && isGrabbing) {
                event = ACTION_MOVE_MOTION;
                CGPoint prevLocationInView = [touchEvent previousLocationInView:self.rootView];
                locationInView.x -= prevLocationInView.x;
                locationInView.y -= prevLocationInView.y;
            }
            [self sendTouchPoint:locationInView withEvent:event];
        }
    //}
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;

    for (UIPress *press in presses) {
        if (press.key != nil && [KeyboardInput sendKeyEvent:press.key down:YES]) {
            handled = YES;
        }
    }
    

    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;

    for (UIPress *press in presses) {
        if (press.key != nil && [KeyboardInput sendKeyEvent:press.key down:NO]) {
            handled = YES;
        }
    }
    

    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

- (BOOL)prefersPointerLocked {
    return GCMouse.mice.count > 0 && (isGrabbing || virtualMouseEnabled);
}

- (void)registerMouseCallbacks:(GCMouse *)mouse {
    NSLog(@"Input: Got mouse %@", mouse);
    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput * _Nonnull mouse, float deltaX, float deltaY) {
        if (!self.view.window.windowScene.pointerLockState.locked) {
            return;
        }
        [self sendTouchPoint:CGPointMake(deltaX, -deltaY) withEvent:ACTION_MOVE_MOTION];
    };

    mouse.mouseInput.leftButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_LEFT, pressed, 0);
    };
    mouse.mouseInput.middleButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_MIDDLE, pressed, 0);
    };
    mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_RIGHT, pressed, 0);
    };
    // GLFW can handle up to 8 mouse buttons, the first 3 buttons are reserved for left,middle,right
    for (int i = 0; i < MIN(mouse.mouseInput.auxiliaryButtons.count, 5); i++) {
        mouse.mouseInput.auxiliaryButtons[i].pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
            CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_4 + i, pressed, 0);
        };
    }

    mouse.mouseInput.scroll.xAxis.valueChangedHandler = ^(GCControllerAxisInput * _Nonnull axis, float value) {
        // Workaround MC-121772 (macOS/iOS feature)
        CallbackBridge_nativeSendScroll(value, value);
    };
    mouse.mouseInput.scroll.yAxis.valueChangedHandler = ^(GCControllerAxisInput * _Nonnull axis, float value) {
        // Workaround MC-121772 (macOS/iOS feature)
        CallbackBridge_nativeSendScroll(-value, -value);
    };

    if (getPrefBool(@"control.hardware_hide")) {
        self.ctrlView.hidden = YES;
    }
}

- (void)surfaceOnClick:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateEnded){
        if(self.shouldTriggerHaptic) {
            [self.lightHaptic impactOccurred];
        }
    }
    
    if (!self.shouldTriggerClick) return;

    if (sender.state == UIGestureRecognizerStateRecognized) {
        if (currentHotbarSlot == -1) {
            if (!self.enableMouseGestures) return;
            CallbackBridge_nativeSendMouseButton(isGrabbing == JNI_TRUE ?
                GLFW_MOUSE_BUTTON_RIGHT : GLFW_MOUSE_BUTTON_LEFT, 1, 0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 33 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                CallbackBridge_nativeSendMouseButton(isGrabbing == JNI_TRUE ?
                    GLFW_MOUSE_BUTTON_RIGHT : GLFW_MOUSE_BUTTON_LEFT, 0, 0);
            });
        } else {
            CallbackBridge_nativeSendKey(currentHotbarSlot, 0, 1, 0);
            CallbackBridge_nativeSendKey(currentHotbarSlot, 0, 0, 0);
        }
    }
}

- (void)surfaceOnDoubleClick:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateEnded){
        if(self.shouldTriggerHaptic) {
            [self.lightHaptic impactOccurred];
        }
    }
    
    if (sender.state == UIGestureRecognizerStateRecognized && isGrabbing) {
        CGFloat screenScale = [[UIScreen mainScreen] scale];
        CGPoint point = [sender locationInView:self.rootView];
        int hotbarSlot = self.enableHotbarGestures ?
            callback_SurfaceViewController_touchHotbar(point.x * screenScale, point.y * screenScale) : -1;
        if (hotbarSlot != -1 && currentHotbarSlot == hotbarSlot) {
            CallbackBridge_nativeSendKey(GLFW_KEY_F, 0, 1, 0);
            CallbackBridge_nativeSendKey(GLFW_KEY_F, 0, 0, 0);
        }
    }
}

- (void)surfaceOnHover:(UIGestureRecognizer *)sender {
    if (isGrabbing) return;
    
    CGPoint point = [sender locationInView:self.rootView];
    // NSLog(@"Mouse move!!");
    // NSLog(@"Mouse pos = %f, %f", point.x, point.y);
    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
            [self sendTouchPoint:point withEvent:ACTION_DOWN];
            break;
        case UIGestureRecognizerStateChanged:
            [self sendTouchPoint:point withEvent:ACTION_MOVE];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self sendTouchPoint:point withEvent:ACTION_UP];
            break;
        default:
            // point = CGPointMake(-1, -1);
            break;
    }
}

-(void)surfaceOnLongpress:(UILongPressGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateEnded){
        if(self.shouldTriggerHaptic) {
            [self.mediumHaptic impactOccurred];
        }
    }
    
    if (!self.slideableHotbar) {
        CGPoint location = [sender locationInView:self.rootView];
        CGFloat screenScale = UIScreen.mainScreen.scale;
        currentHotbarSlot = self.enableHotbarGestures ?
            callback_SurfaceViewController_touchHotbar(location.x * screenScale, location.y * screenScale) : -1;
    }
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.shouldTriggerClick = NO;
        if (currentHotbarSlot == -1) {

            if (self.enableMouseGestures)
                CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_LEFT, 1, 0);
        } else {
            CallbackBridge_nativeSendKey(GLFW_KEY_Q, 0, 1, 0);
        }
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        // Nothing to do here, already handled in touchesMoved
    } else if (sender.state == UIGestureRecognizerStateCancelled
        || sender.state == UIGestureRecognizerStateFailed
            || sender.state == UIGestureRecognizerStateEnded)
    {
        if (currentHotbarSlot == -1) {
            if (self.enableMouseGestures)
                CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_LEFT, 0, 0);
        } else {
            CallbackBridge_nativeSendKey(GLFW_KEY_Q, 0, 0, 0);
        }
    }
}

- (void)surfaceOnTouchesScroll:(UIPanGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateEnded){
        if(self.shouldTriggerHaptic) {
            [self.lightHaptic impactOccurred];
        }
    }
    
    if (isGrabbing) return;
    if (sender.state == UIGestureRecognizerStateBegan ||
        sender.state == UIGestureRecognizerStateChanged ||
        sender.state == UIGestureRecognizerStateEnded) {
        CGPoint velocity = [sender velocityInView:self.rootView];
        if (velocity.x != 0.0f || velocity.y != 0.0f) {
            CallbackBridge_nativeSendScroll(velocity.x/self.view.frame.size.width, velocity.y/self.view.frame.size.height);
        }
    }
}

#pragma mark - Input view stuff

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    CallbackBridge_nativeSendKey(GLFW_KEY_ENTER, 0, 1, 0);
    CallbackBridge_nativeSendKey(GLFW_KEY_ENTER, 0, 0, 0);
    textField.text = @" ";
    return YES;
}

#pragma mark - On-screen button functions

- (void)executebtn:(ControlButton *)sender withAction:(int)action {
    int held = action == ACTION_DOWN;
    for (int i = 0; i < 4; i++) {
        int keycode = ((NSNumber *)sender.properties[@"keycodes"][i]).intValue;
        if (keycode < 0) {
            switch (keycode) {
                case SPECIALBTN_KEYBOARD:
                    if (held == 0) {
                        if (self.inputTextField.isFirstResponder) {
                            [self.inputTextField resignFirstResponder];
                            self.inputTextField.alpha = 1.0f;
                        } else {
                            [self.inputTextField becomeFirstResponder];
                            // Insert an undeletable space
                            self.inputTextField.text = @" ";
                        }
                    }
                    break;

                case SPECIALBTN_MOUSEPRI:
                    CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_LEFT, held, 0);
                    break;

                case SPECIALBTN_MOUSESEC:
                    CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_RIGHT, held, 0);
                    break;

                case SPECIALBTN_MOUSEMID:
                    CallbackBridge_nativeSendMouseButton(GLFW_MOUSE_BUTTON_MIDDLE, held, 0);
                    break;

                case SPECIALBTN_TOGGLECTRL:
                    [self executebtn_special_togglebtn:held];
                    break;

                case SPECIALBTN_SCROLLDOWN:
                    if (!held) {
                        CallbackBridge_nativeSendScroll(0.0, 1.0);
                    }
                    break;

                case SPECIALBTN_SCROLLUP:
                    if (!held) {
                        CallbackBridge_nativeSendScroll(0.0, -1.0);
                    }
                    break;

                case SPECIALBTN_VIRTUALMOUSE:
                    if (!isGrabbing && !held) {
                        virtualMouseEnabled = !virtualMouseEnabled;
                        self.mousePointerView.hidden = !virtualMouseEnabled;
                        setPrefBool(@"control.virtmouse_enable", virtualMouseEnabled);
                        [self setNeedsUpdateOfPrefersPointerLocked];
                    }
                    break;

                case SPECIALBTN_MENU:
                    if (!held) {
                        [self actionOpenNavigationMenu];
                    }
                    break;

                default:
                    NSLog(@"Warning: button %@ sent unknown special keycode: %d", sender.titleLabel.text, keycode);
                    break;
            }
        } else if (keycode > 0) {
            // there's no key id 0, but we accidentally used -1 as a special key id, so we had to do that
            // if (keycode == 0) { keycode = -1; }
            // at the moment, send unknown keycode does nothing, may even cause performance issue, so ignore it
            CallbackBridge_nativeSendKey(keycode, 0, held, 0);
        }
    }
}

- (void)executebtn_down:(ControlButton *)sender
{
    if(self.shouldTriggerHaptic) {
        [self.lightHaptic impactOccurred];
    }
    
    if (sender.savedBackgroundColor == nil) {
        [self executebtn:sender withAction:ACTION_DOWN];
    }
    if ([self.swipeableButtons containsObject:sender]) {
        self.swipingButton = sender;
    }
}

- (void)executebtn_swipe:(UIPanGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateEnded) {
        [self executebtn_up:self.swipingButton isOutside:NO];
        return;
    }
    CGPoint location = [sender locationInView:self.ctrlView];
    for (ControlButton *button in self.swipeableButtons) {
        if (CGRectContainsPoint(button.frame, location) && (ControlButton *)self.swipingButton != button) {
            [self executebtn_up:self.swipingButton isOutside:NO];
            self.swipingButton = (ControlButton *)button;
            [self executebtn:self.swipingButton withAction:ACTION_DOWN];
            break;
        }
    }
}

- (ControlButton *)movementButtonForKeycode:(int)keycode {
    for (ControlButton *button in self.swipeableButtons) {
        if (button.hidden || !button.enabled) continue;
        for (NSNumber *value in button.properties[@"keycodes"]) {
            if (value.intValue == keycode) return button;
        }
    }
    return nil;
}

- (BOOL)isFluidMovementButton:(ControlButton *)button {
    if (!button) return NO;
    for (NSNumber *value in button.properties[@"keycodes"]) {
        int keycode = value.intValue;
        if (keycode == GLFW_KEY_W || keycode == GLFW_KEY_A ||
            keycode == GLFW_KEY_S || keycode == GLFW_KEY_D) {
            return YES;
        }
    }
    return NO;
}

- (UIView *)diagonalIndicatorNamed:(NSString *)name
                            first:(ControlButton *)first
                           second:(ControlButton *)second {
    UIView *indicator = self.diagonalIndicators[name];
    if (!indicator) {
        UIVisualEffectView *glass = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
        glass.userInteractionEnabled = NO;
        glass.layer.cornerRadius = 11.0;
        glass.clipsToBounds = YES;
        UIImageView *icon = [[UIImageView alloc]
            initWithImage:[UIImage systemImageNamed:name]];
        icon.tintColor = UIColor.whiteColor;
        icon.frame = CGRectMake(4, 4, 14, 14);
        [glass.contentView addSubview:icon];
        glass.bounds = CGRectMake(0, 0, 22, 22);
        glass.alpha = 0;
        [self.ctrlView addSubview:glass];
        self.diagonalIndicators[name] = glass;
        indicator = glass;
    }
    return indicator;
}

- (void)updateDirectionRingAtCenter:(CGPoint)center radius:(CGFloat)radius {
    if (!self.directionRingLayer) {
        self.directionRingLayer = [CAShapeLayer layer];
        self.directionRingLayer.fillColor = UIColor.clearColor.CGColor;
        self.directionRingLayer.strokeColor =
            [UIColor.whiteColor colorWithAlphaComponent:0.42].CGColor;
        self.directionRingLayer.lineWidth = 2.0;
        self.directionRingLayer.lineCap = kCALineCapRound;
        self.directionRingLayer.opacity = 0;
        [self.ctrlView.layer insertSublayer:self.directionRingLayer atIndex:0];
    }
    self.directionRingLayer.path =
        [UIBezierPath bezierPathWithArcCenter:center radius:radius
            startAngle:0 endAngle:(CGFloat)(M_PI * 2.0) clockwise:YES].CGPath;
}

- (void)setVisibleDiagonalIndicator:(UIView *)visible {
    for (UIView *indicator in self.diagonalIndicators.allValues) {
        CGFloat target = indicator == visible ? 1.0 : 0.0;
        if (indicator.alpha != target) {
            [UIView animateWithDuration:0.1 animations:^{ indicator.alpha = target; }];
        }
    }
}

- (void)applyFluidButtons:(NSArray<ControlButton *> *)desired {
    for (ControlButton *button in self.fluidActiveButtons.copy) {
        if (![desired containsObject:button]) {
            [self executebtn:button withAction:ACTION_UP];
            [self.fluidActiveButtons removeObject:button];
        }
    }
    for (ControlButton *button in desired) {
        if (![self.fluidActiveButtons containsObject:button]) {
            if (button != self.swipingButton) {
                [self executebtn:button withAction:ACTION_DOWN];
            }
            [self.fluidActiveButtons addObject:button];
            if (self.shouldTriggerHaptic) [self.lightHaptic impactOccurred];
        }
    }
}

- (void)handleFluidButtonPan:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        [self applyFluidButtons:@[]];
        self.fluidMovementCaptured = NO;
        [self setVisibleDiagonalIndicator:nil];
        self.directionRingLayer.opacity = 0;
        return;
    }
    if (gesture.state != UIGestureRecognizerStateBegan &&
        gesture.state != UIGestureRecognizerStateChanged) return;

    CGPoint point = [gesture locationInView:self.ctrlView];
    ControlButton *up = [self movementButtonForKeycode:GLFW_KEY_W];
    ControlButton *left = [self movementButtonForKeycode:GLFW_KEY_A];
    ControlButton *down = [self movementButtonForKeycode:GLFW_KEY_S];
    ControlButton *right = [self movementButtonForKeycode:GLFW_KEY_D];
    NSArray<ControlButton *> *movementButtons =
        (up && left && down && right) ? @[up, left, down, right] : @[];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.fluidGestureOrigin = point;
        self.fluidMovementCaptured = NO;
        for (ControlButton *button in movementButtons) {
            CGRect generousHitArea = CGRectInset(button.frame, -14.0, -14.0);
            if (!button.hidden && button.enabled &&
                CGRectContainsPoint(generousHitArea, self.fluidGestureOrigin)) {
                self.fluidMovementCaptured = YES;
                break;
            }
        }
    }

    // Once a gesture starts on W/A/S/D, the whole circular pad belongs to the
    // fluid controller. Do not let the old rectangular button hit test win.
    if (!self.fluidMovementCaptured) {
        [self applyFluidButtons:@[]];
        return;
    }

    CGPoint center = CGPointMake(
        (up.center.x + left.center.x + down.center.x + right.center.x) / 4.0,
        (up.center.y + left.center.y + down.center.y + right.center.y) / 4.0);
    CGFloat radius = (
        hypot(up.center.x - center.x, up.center.y - center.y) +
        hypot(left.center.x - center.x, left.center.y - center.y) +
        hypot(down.center.x - center.x, down.center.y - center.y) +
        hypot(right.center.x - center.x, right.center.y - center.y)) / 4.0;
    radius = MAX(radius, 30.0);
    [self updateDirectionRingAtCenter:center radius:radius];

    CGFloat dx = point.x - center.x;
    CGFloat dy = point.y - center.y;
    CGFloat distance = hypot(dx, dy);
    if (distance < 10.0) {
        // A tiny centre dead zone prevents noisy direction flipping while the
        // finger crosses the middle; keep the last direction pressed.
        return;
    }

    // Eight equal 45-degree sectors. A diagonal is represented by holding both
    // adjacent Minecraft movement keys, e.g. W + D for upper-right.
    CGFloat diagonalThreshold = tan((CGFloat)M_PI / 8.0);
    CGFloat absX = fabs(dx), absY = fabs(dy);
    NSMutableArray<ControlButton *> *desired = [NSMutableArray arrayWithCapacity:2];
    BOOL useHorizontal = absY == 0 || absX / absY > diagonalThreshold;
    BOOL useVertical = absX == 0 || absY / absX > diagonalThreshold;
    if (useVertical) [desired addObject:(dy < 0 ? up : down)];
    if (useHorizontal) [desired addObject:(dx < 0 ? left : right)];
    [self applyFluidButtons:desired];

    NSArray *pairs = @[
        @[up ?: NSNull.null, left ?: NSNull.null, @"arrow.up.left"],
        @[up ?: NSNull.null, right ?: NSNull.null, @"arrow.up.right"],
        @[down ?: NSNull.null, left ?: NSNull.null, @"arrow.down.left"],
        @[down ?: NSNull.null, right ?: NSNull.null, @"arrow.down.right"]
    ];
    for (NSArray *pair in pairs) {
        if (pair[0] == NSNull.null || pair[1] == NSNull.null) continue;
        ControlButton *first = pair[0], *second = pair[1];
        UIView *indicator = [self diagonalIndicatorNamed:pair[2]
            first:first second:second];
        BOOL pointsLeft = [pair[2] containsString:@"left"];
        BOOL pointsUp = [pair[2] containsString:@"up"];
        CGFloat diagonal = radius / sqrt(2.0);
        indicator.center = CGPointMake(
            center.x + (pointsLeft ? -diagonal : diagonal),
            center.y + (pointsUp ? -diagonal : diagonal));
        if ([desired containsObject:first] && [desired containsObject:second]) {
            [self setVisibleDiagonalIndicator:indicator];
            self.directionRingLayer.opacity = 1;
            return;
        }
    }
    [self setVisibleDiagonalIndicator:nil];
    self.directionRingLayer.opacity = 1;
}

- (void)executebtn_up:(ControlButton *)sender isOutside:(BOOL)isOutside
{
    // UIKit may emit TouchUpOutside after the unified pad has captured the
    // gesture. Releasing here would desynchronise the actual Minecraft key
    // state from fluidActiveButtons and make a full circle stop on W/A/S/D.
    // The fluid gesture owns all four releases until the finger really lifts.
    if (self.fluidMovementCaptured && [self isFluidMovementButton:sender]) {
        return;
    }
    if (self.swipingButton == sender) {
        [self executebtn:self.swipingButton withAction:ACTION_UP];
        self.swipingButton = nil;
    } else if (sender.savedBackgroundColor == nil) {
        [self executebtn:sender withAction:ACTION_UP];
        return;
    }

    if (isOutside || sender.savedBackgroundColor == nil) {
        return;
    }

    sender.isToggleOn = !sender.isToggleOn;
    if (sender.isToggleOn) {
        sender.backgroundColor = [self.view.tintColor colorWithAlphaComponent:CGColorGetAlpha(sender.savedBackgroundColor.CGColor)];
        [self executebtn:sender withAction:ACTION_DOWN];
    } else {
        sender.backgroundColor = sender.savedBackgroundColor;
        [self executebtn:sender withAction:ACTION_UP];
    }

    if(self.shouldTriggerHaptic) {
        [self.lightHaptic impactOccurred];
    }
}

- (void)executebtn_up_inside:(ControlButton *)sender {
    [self executebtn_up:sender isOutside:NO];
}

- (void)executebtn_up_outside:(ControlButton *)sender {
    [self executebtn_up:sender isOutside:YES];
}

- (void)executebtn_special_togglebtn:(int)held {
    if (held) return;
    self.toggleHidden = !self.toggleHidden;
    [self updateControlHiddenState:self.toggleHidden];
}

#pragma mark - Input: On-screen touch events

int touchesMovedCount;
// Equals to Android ACTION_DOWN
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    int i = 0;
    for (UITouch *touch in touches) {
        if (touch.type == UITouchTypeIndirectPointer) {
            continue; // handle this in a different place
        }
        CGPoint locationInView = [touch locationInView:self.rootView];
        CGFloat screenScale = [[UIScreen mainScreen] scale];
        currentHotbarSlot = self.enableHotbarGestures ?
            callback_SurfaceViewController_touchHotbar(locationInView.x * screenScale, locationInView.y * screenScale) : -1;
        if ([self isTouchInactive:self.hotbarTouch] && currentHotbarSlot != -1) {
            self.hotbarTouch = touch;
        }
        if ([self isTouchInactive:self.primaryTouch] && currentHotbarSlot == -1) {
            self.primaryTouch = touch;
        }
        [self sendTouchEvent:touch withUIEvent:event withEvent:ACTION_DOWN];
        break;
    }
}

// Equals to Android ACTION_MOVE
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];

    for (UITouch *touch in touches) {
        if (touch.type == UITouchTypeIndirectPointer) {
            if (!isGrabbing && !virtualMouseEnabled) {
                CGPoint point = [touch locationInView:self.rootView];
                [self sendTouchPoint:point withEvent:ACTION_MOVE];
            }
            continue; // handle this in a different place
        }
        if (self.hotbarTouch != touch && [self isTouchInactive:self.primaryTouch]) {
            // Replace the inactive touch with the current active touch
            self.primaryTouch = touch;
            [self sendTouchEvent:touch withUIEvent:event withEvent:ACTION_DOWN];
        }
        [self sendTouchEvent:touch withUIEvent:event withEvent:ACTION_MOVE];
    }
}

// For ACTION_UP and ACTION_CANCEL
- (void)touchesEndedGlobal:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        if (touch.type == UITouchTypeIndirectPointer) {
            continue; // handle this in a different place
        }
        [self sendTouchEvent:touch withUIEvent:event withEvent:ACTION_UP];
    }
}

// Equals to Android ACTION_UP
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    [self touchesEndedGlobal:touches withEvent:event];
}

// Equals to Android ACTION_CANCEL
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    [self touchesEndedGlobal:touches withEvent:event];
}

+ (BOOL)isRunning {
    return [UIWindow.mainWindow.rootViewController isKindOfClass:SurfaceViewController.class];
}

+ (GameSurfaceView *)surface {
    return pojavWindow;
}

@end
