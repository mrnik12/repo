#import <CoreData/CoreData.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char FixtureMarker;

static unsigned char LSHexDigit(unsigned char digit) {
    if (digit >= '0' && digit <= '9') {
        return digit - '0';
    }
    if (digit >= 'a' && digit <= 'f') {
        return digit - 'a' + 10;
    }
    return 0xff;
}

static NSData *LSDecodeArtwork(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSData *hex = [value dataUsingEncoding:NSASCIIStringEncoding];
    if (!hex.length || hex.length > 512000 || hex.length % 2) {
        return nil;
    }
    const unsigned char *source = (const unsigned char *)hex.bytes;
    NSMutableData *image = [NSMutableData dataWithLength:hex.length / 2];
    unsigned char *destination = (unsigned char *)image.mutableBytes;
    for (NSUInteger i = 0; i < image.length; ++i) {
        unsigned char high = LSHexDigit(source[i * 2]);
        unsigned char low = LSHexDigit(source[i * 2 + 1]);
        if (high > 15 || low > 15) {
            return nil;
        }
        destination[i] = (high << 4) | low;
    }
    return [UIImage imageWithData:image] ? image : nil;
}


@interface SHTagResultDefaultParentViewController_iPhone : UIViewController
- (id)initWithTagResult:(NSManagedObject *)result;
@end

%hook SHTagResultMO

- (NSString *)displayTitle {
    if (objc_getAssociatedObject(self, &FixtureMarker)) {
        return [objc_getAssociatedObject(self, &FixtureMarker) objectForKey:@"title"];
    }
    return %orig;
}

- (NSString *)artistString {
    if (objc_getAssociatedObject(self, &FixtureMarker)) {
        return [objc_getAssociatedObject(self, &FixtureMarker) objectForKey:@"artist"];
    }
    return %orig;
}

%end

@interface LSResultPresenter : NSObject {
    UIWindow *_previewWindow;
    UIWindow *_previousWindow;
}
+ (void)showTitle:(NSString *)title artist:(NSString *)artist artwork:(NSData *)artwork;
- (void)openTitle:(NSString *)title artist:(NSString *)artist artwork:(NSData *)artwork;
@end

@implementation LSResultPresenter

- (void)closePreview {
    _previewWindow.hidden = YES;
    [_previousWindow makeKeyWindow];
    [_previewWindow release];
    _previewWindow = nil;
    [_previousWindow release];
    _previousWindow = nil;
}

+ (void)showTitle:(NSString *)title artist:(NSString *)artist artwork:(NSData *)artwork {
    static LSResultPresenter *presenter;
    if (!presenter) {
        presenter = [[LSResultPresenter alloc] init];
    }
    [presenter openTitle:title artist:artist artwork:artwork];
}

- (void)openTitle:(NSString *)title artist:(NSString *)artist artwork:(NSData *)artwork {
    if (_previewWindow) {
        return;
    }
    @try {
        NSURL *modelURL = [[NSBundle mainBundle]
            URLForResource:@"ShazamDataModel 5.5.1-0"
            withExtension:@"mom"
            subdirectory:@"ShazamDataModel.momd"];
        if (!modelURL) {
            [NSException raise:NSInternalInconsistencyException format:@"The 5.5.1 data model was not found."];
        }
        NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL] autorelease];
        NSEntityDescription *resultEntity = nil;
        for (NSEntityDescription *entity in model.entities) {
            if ([entity.managedObjectClassName isEqualToString:@"SHTagResultMO"]) {
                resultEntity = entity;
                break;
            }
        }

        Class resultClass = %c(SHTagResultMO);
        Class controllerClass = %c(SHTagResultDefaultParentViewController_iPhone);
        if (!resultEntity) {
            [NSException raise:NSInternalInconsistencyException format:@"The Core Data model has no SHTagResultMO entity."];
        }
        if (!resultClass || !controllerClass) {
            [NSException raise:NSInternalInconsistencyException
                        format:@"Missing runtime class: %@.",
                               !resultClass ? @"SHTagResultMO" : @"SHTagResultDefaultParentViewController_iPhone"];
        }

        NSManagedObject *result = [[[resultClass alloc] initWithEntity:resultEntity
                                     insertIntoManagedObjectContext:nil] autorelease];
        objc_setAssociatedObject(result, &FixtureMarker, @{@"title": title, @"artist": artist}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [result setValue:title forKey:@"name"];
        [result setValue:artist forKey:@"subtitle"];
        [result setValue:artist forKey:@"cachedArtistString"];
        [result setValue:@"music" forKey:@"type"];
        [result setValue:[NSDate date] forKey:@"date"];
        [result setValue:@YES forKey:@"completeResult"];
        if (artwork.length) {
            [result setValue:artwork forKey:@"albumArtData"];
            [result setValue:artwork forKey:@"albumArtThumbnailData"];
        }

        SHTagResultDefaultParentViewController_iPhone *screen =
            [[[controllerClass alloc] initWithTagResult:result] autorelease];
        if (!screen) {
            [NSException raise:NSInternalInconsistencyException format:@"Shazam could not create its result screen."];
        }
        // Exercise the native screen before presenting so setup errors are visible.
        [screen view];
        screen.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
            target:self action:@selector(closePreview)] autorelease];
        UINavigationController *navigation =
            [[[UINavigationController alloc] initWithRootViewController:screen] autorelease];
        _previousWindow = [[UIApplication sharedApplication].keyWindow retain];
        _previewWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _previewWindow.rootViewController = navigation;
        [_previewWindow makeKeyAndVisible];
    } @catch (NSException *exception) {
        if (_previewWindow) {
            [self closePreview];
        }
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Result preview unavailable"
            message:exception.reason delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
        [error show];
    }
}

@end

#import <AVFoundation/AVFoundation.h>
#import "RelayConfig.h"

#import <math.h>

@interface SHTagButtonView_iPhone : UIView
- (UIView *)audioReactiveView;
- (void)startTaggingAnimation;
- (void)stopTaggingAnimation;
@end

@interface SHTagViewController_iPhone : UIViewController
- (SHTagButtonView_iPhone *)taggingView;
- (UIButton *)cancelTaggingButton;
- (UILabel *)taggingStatusLabel;
@end

// The native visualizer requests levels through these two methods.
@interface LSAnimationMeter : NSObject {
    float _level;
}
- (void)updateFromRecorder:(AVAudioRecorder *)recorder;
- (float)levelForBand:(id)band;
- (float)trebleLevel;
@end

@implementation LSAnimationMeter

- (void)updateFromRecorder:(AVAudioRecorder *)recorder {
    float level = 0;
    if (recorder.isRecording) {
        [recorder updateMeters];
        float power = [recorder averagePowerForChannel:0];
        level = fminf(1.0f, fmaxf(0.0f, (power + 52.0f) / 46.0f));
    }
    _level += (level - _level) * (level > _level ? 0.65f : 0.20f);
}

- (float)levelForBand:(id)band {
    return _level;
}

- (float)trebleLevel {
    return _level;
}

@end

static id ActiveAnimationView;
static LSAnimationMeter *FrameMeter;


static BOOL LSRecognitionEnabled(void) {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/org.legacyshazam.settings.plist"];
    id enabled = [preferences objectForKey:@"Enabled"];
    return ![enabled isKindOfClass:[NSNumber class]] || [enabled boolValue];
}

@interface LSRecognition : NSObject <AVAudioRecorderDelegate> {
    AVAudioRecorder *_recorder;
    NSString *_previousCategory;
    BOOL _busy;
    BOOL _waitingForRelay;
    NSUInteger _relayAttempt;
    UILabel *_statusLabel;
    NSString *_previousStatus;
    BOOL _statusWasHidden;
    CGFloat _statusAlpha;
    BOOL _statusWasChanged;
    UIButton *_cancelButton;
    BOOL _cancelWasHidden;
    BOOL _cancelWasEnabled;
    CGFloat _cancelOriginalAlpha;
    SHTagButtonView_iPhone *_dial;
    LSAnimationMeter *_animationMeter;
}
- (void)startWithDial:(SHTagButtonView_iPhone *)dial cancelButton:(UIButton *)button statusLabel:(UILabel *)statusLabel;
- (BOOL)cancelListening;
- (void)submitAudio:(NSData *)audio;
- (void)waitForRelayWithAudio:(NSData *)audio deadline:(NSTimeInterval)deadline attempt:(NSUInteger)attempt;
- (LSAnimationMeter *)updateAnimationMeter;
@end

@implementation LSRecognition

- (void)showMessage:(NSString *)message {
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"ShazamX"
        message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
    [alert show];
}

- (LSAnimationMeter *)updateAnimationMeter {
    [_animationMeter updateFromRecorder:_recorder];
    return _animationMeter;
}

- (void)stopAnimation {
    if (!_dial) {
        return;
    }
    ActiveAnimationView = nil;
    [_dial stopTaggingAnimation];
    [_dial release];
    _dial = nil;
    [_animationMeter release];
    _animationMeter = nil;
}

- (void)showWaitingStatus {
    if (_statusWasChanged) {
        return;
    }
    _statusWasChanged = YES;
    _previousStatus = [_statusLabel.text copy];
    _statusWasHidden = _statusLabel.hidden;
    _statusAlpha = _statusLabel.alpha;
    _statusLabel.text = @"Waking recognition server...";
    _statusLabel.hidden = NO;
    _statusLabel.alpha = 1.0;
}

- (void)restoreStatusLabel {
    if (_statusWasChanged) {
        _statusLabel.text = _previousStatus;
        _statusLabel.hidden = _statusWasHidden;
        _statusLabel.alpha = _statusAlpha;
        [_previousStatus release];
        _previousStatus = nil;
        _statusWasChanged = NO;
    }
}

- (void)finish {
    _waitingForRelay = NO;
    [self restoreStatusLabel];
    [_statusLabel release];
    _statusLabel = nil;
    [self restoreCancelButton];
    [self stopAnimation];
    _busy = NO;
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
}

- (void)showCancelButton:(UIButton *)button {
    _cancelButton = [button retain];
    _cancelWasHidden = button.hidden;
    _cancelWasEnabled = button.enabled;
    _cancelOriginalAlpha = button.alpha;
    button.hidden = NO;
    button.enabled = YES;
    button.alpha = 1.0;
}

- (void)restoreCancelButton {
    _cancelButton.hidden = _cancelWasHidden;
    _cancelButton.enabled = _cancelWasEnabled;
    _cancelButton.alpha = _cancelOriginalAlpha;
    [_cancelButton release];
    _cancelButton = nil;
}

- (void)discardRecorder {
    NSURL *url = _recorder.url;
    if (url) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }
    _recorder.delegate = nil;
    [_recorder release];
    _recorder = nil;
    if (_previousCategory) {
        [[AVAudioSession sharedInstance] setCategory:_previousCategory error:NULL];
        [_previousCategory release];
        _previousCategory = nil;
    }
}

- (BOOL)cancelListening {
    if (_waitingForRelay) {
        [self finish];
        return YES;
    }
    if (!_recorder) {
        return NO;
    }
    _recorder.delegate = nil;
    [_recorder stop];
    [self discardRecorder];
    [self finish];
    return YES;
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    [self cancelListening];
    [self stopAnimation];
}

- (void)startWithDial:(SHTagButtonView_iPhone *)dial cancelButton:(UIButton *)button statusLabel:(UILabel *)statusLabel {
    if (_busy || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return;
    }
    _busy = YES;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    _previousCategory = [session.category copy];
    NSError *error = nil;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"wav"]];
    NSURL *url = [NSURL fileURLWithPath:path];
    if ([session setCategory:AVAudioSessionCategoryRecord error:&error]
            && [session setActive:YES error:&error]) {
        _recorder = [[AVAudioRecorder alloc] initWithURL:url settings:@{
            AVFormatIDKey: @(kAudioFormatLinearPCM),
            AVSampleRateKey: @16000,
            AVNumberOfChannelsKey: @1,
            AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsBigEndianKey: @NO,
            AVLinearPCMIsFloatKey: @NO
        } error:&error];
        _recorder.delegate = self;
        _recorder.meteringEnabled = YES;
        if ([_recorder recordForDuration:8.0]) {
            [self showCancelButton:button];
            _statusLabel = [statusLabel retain];
            _dial = [dial retain];
            _animationMeter = _dial ? [[LSAnimationMeter alloc] init] : nil;
            ActiveAnimationView = [_dial audioReactiveView];
            [_dial startTaggingAnimation];
            ActiveAnimationView = [_dial audioReactiveView];
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
            return;
        }
    }
    [self discardRecorder];
    [self finish];
    [self showMessage:error.localizedDescription ?: @"The microphone could not start."];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)success {
    if (recorder != _recorder) {
        return;
    }
    NSData *audio = success ? [NSData dataWithContentsOfURL:recorder.url] : nil;
    [self discardRecorder];
    if (!audio.length) {
        [self finish];
        [self showMessage:@"No audio was recorded."];
        return;
    }

    if ([[[NSURL URLWithString:LS_RELAY_URL] scheme] isEqualToString:@"https"]) {
        _waitingForRelay = YES;
        [self waitForRelayWithAudio:audio deadline:[NSProcessInfo processInfo].systemUptime + 78
                           attempt:++_relayAttempt];
    } else {
        [self restoreCancelButton];
        [self submitAudio:audio];
    }
}

- (void)waitForRelayWithAudio:(NSData *)audio deadline:(NSTimeInterval)deadline attempt:(NSUInteger)attempt {
    if (!_waitingForRelay || attempt != _relayAttempt) {
        return;
    }
    NSTimeInterval remaining = deadline - [NSProcessInfo processInfo].systemUptime;
    if (remaining <= 0) {
        [self finish];
        [self showMessage:@"The hosted relay did not wake up. Try tagging again."];
        return;
    }

    NSURL *relayURL = [NSURL URLWithString:LS_RELAY_URL];
    NSURL *healthURL = [[NSURL URLWithString:@"/health" relativeToURL:relayURL] absoluteURL];
    NSURLRequest *request = [NSURLRequest requestWithURL:healthURL
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:MIN(12, remaining)];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (!_waitingForRelay || attempt != _relayAttempt) {
            return;
        }
        if (!LSRecognitionEnabled() || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            [self finish];
            return;
        }
        if ([error.domain isEqualToString:NSURLErrorDomain] &&
                (error.code == NSURLErrorNotConnectedToInternet || error.code == NSURLErrorSecureConnectionFailed ||
                 error.code == NSURLErrorServerCertificateUntrusted)) {
            [self finish];
            [self showMessage:error.localizedDescription];
            return;
        }
        id body = !error && data.length && [(NSHTTPURLResponse *)response statusCode] == 200
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if ([body isKindOfClass:[NSDictionary class]] && [[body objectForKey:@"ok"] isEqual:@YES]) {
            _waitingForRelay = NO;
            [self restoreStatusLabel];
            [self restoreCancelButton];
            [self submitAudio:audio];
            return;
        }
        [self showWaitingStatus];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self waitForRelayWithAudio:audio deadline:deadline attempt:attempt];
        });
    }];
}


- (void)submitAudio:(NSData *)audio {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:LS_RELAY_URL]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:32];
    request.HTTPMethod = @"POST";
    request.HTTPBody = audio;
    [request setValue:@"audio/wav" forHTTPHeaderField:@"Content-Type"];
    if ([LS_RELAY_TOKEN length]) {
        [request setValue:LS_RELAY_TOKEN forHTTPHeaderField:@"X-Relay-Token"];
    }
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        [self finish];
        if (!LSRecognitionEnabled() || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            return;
        }
        if (error) {
            [self showMessage:[NSString stringWithFormat:@"Could not contact the recognition server. %@", error.localizedDescription]];
            return;
        }
        id payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![payload isKindOfClass:[NSDictionary class]]) {
            [self showMessage:@"The recognition server returned an invalid response."];
            return;
        }
        NSString *detail = [payload objectForKey:@"detail"];
        if ([(NSHTTPURLResponse *)response statusCode] != 200) {
            [self showMessage:[detail isKindOfClass:[NSString class]] ? detail : @"Recognition failed."];
            return;
        }
        if (![[payload objectForKey:@"matched"] boolValue]) {
            [self showMessage:@"No match. Try again with the music closer to the phone."];
            return;
        }
        NSString *title = [payload objectForKey:@"title"];
        NSString *artist = [payload objectForKey:@"artist"];
        if (![title isKindOfClass:[NSString class]] || ![artist isKindOfClass:[NSString class]]) {
            [self showMessage:@"The relay returned an incomplete match."];
            return;
        }
        [LSResultPresenter showTitle:title artist:artist
                           artwork:LSDecodeArtwork([payload objectForKey:@"artwork"])];
    }];
}

@end

static LSRecognition *Recognition;

%hook SHTaggingAnimationView_BezierPath
- (void)updateMetering {
    LSAnimationMeter *previousMeter = FrameMeter;
    FrameMeter = self == ActiveAnimationView ? [Recognition updateAnimationMeter] : nil;
    @try {
        %orig;
    } @finally {
        FrameMeter = previousMeter;
    }
}
%end

%hook SHTaggingAnimationView_PNG
- (void)updateMetering {
    LSAnimationMeter *previousMeter = FrameMeter;
    FrameMeter = self == ActiveAnimationView ? [Recognition updateAnimationMeter] : nil;
    @try {
        %orig;
    } @finally {
        FrameMeter = previousMeter;
    }
}
%end

%hook SHAudioVisualisationSegmentLayer
- (id)audioMetering {
    return FrameMeter ?: %orig;
}
%end

%hook SHAudioVisualisationPNGLayer
- (id)audioMetering {
    return FrameMeter ?: %orig;
}
%end


%hook SHTagViewController_iPhone
- (void)cancelTagging:(id)sender {
    if (![Recognition cancelListening]) {
        %orig;
    }
}

- (void)taggingButtonPressed:(id)sender {
    if (!LSRecognitionEnabled()) {
        %orig;
        return;
    }
    [Recognition startWithDial:[self taggingView] cancelButton:[self cancelTaggingButton] statusLabel:[self taggingStatusLabel]];
}
%end

%ctor {
    if (![[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] isEqualToString:@"572"]) {
        return;
    }
    Recognition = [[LSRecognition alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:Recognition
        selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    %init;
}

