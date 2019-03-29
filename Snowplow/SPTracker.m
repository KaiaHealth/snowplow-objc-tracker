//
//  SPTracker.m
//  Snowplow
//
//  Copyright (c) 2013-2018 Snowplow Analytics Ltd. All rights reserved.
//
//  This program is licensed to you under the Apache License Version 2.0,
//  and you may not use this file except in compliance with the Apache License
//  Version 2.0. You may obtain a copy of the Apache License Version 2.0 at
//  http://www.apache.org/licenses/LICENSE-2.0.
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the Apache License Version 2.0 is distributed on
//  an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
//  express or implied. See the Apache License Version 2.0 for the specific
//  language governing permissions and limitations there under.
//
//  Authors: Jonathan Almeida, Joshua Beemster
//  Copyright: Copyright (c) 2013-2018 Snowplow Analytics Ltd
//  License: Apache License Version 2.0
//

#import "Snowplow.h"
#import "SPTracker.h"
#import "SPEmitter.h"
#import "SPSubject.h"
#import "SPPayload.h"
#import "SPSelfDescribingJson.h"
#import "SPUtilities.h"
#import "SPSession.h"
#import "SPEvent.h"
#import "SPError.h"
#import "SPScreenState.h"
#import "SPInstallTracker.h"

/** A class extension that makes the screen view states mutable internally. */
@interface SPTracker ()

@property (readwrite, nonatomic, strong) SPScreenState * currentScreenState;
@property (readwrite, nonatomic, strong) SPScreenState * previousScreenState;

- (void) populatePreviousScreenState;

/*!
 @brief This method is called to send an auto-tracked screen view event.

 @param notification The notification raised by a UIViewController
 */
- (void) receiveScreenViewNotification:(NSNotification *)notification;

@end

void uncaughtExceptionHandler(NSException *exception) {
    NSArray* backtrace = [exception callStackSymbols];
    // Construct userInfo
    NSMutableDictionary* userInfo = [[NSMutableDictionary alloc] init];
    userInfo[@"stackTrace"] = [NSString stringWithFormat:@"Backtrace:\n%@", backtrace];
    userInfo[@"message"] = [exception reason];
    
    // Send notification to tracker
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"SPExceptionOccurred"
     object:nil
     userInfo:userInfo];
}

@implementation SPTracker {
    NSMutableDictionary *  _trackerData;
    NSString *             _platformContextSchema;
    BOOL                   _dataCollection;
    SPSession *            _session;
    BOOL                   _sessionContext;
    BOOL                   _applicationContext;
    BOOL                   _autotrackScreenViews;
    BOOL                   _lifecycleEvents;
    NSInteger              _foregroundTimeout;
    NSInteger              _backgroundTimeout;
    NSInteger              _checkInterval;
    BOOL                   _builderFinished;
    BOOL                   _exceptionEvents;
}

// SnowplowTracker Builder

+ (instancetype) build:(void(^)(id<SPTrackerBuilder>builder))buildBlock {
    SPTracker* tracker = [[SPTracker alloc] initWithDefaultValues];
    if (buildBlock) {
        buildBlock(tracker);
    }
    [tracker setup];
    [tracker checkInstall];
    return tracker;
}

- (instancetype) initWithDefaultValues {
    self = [super init];
    if (self) {
        _trackerNamespace = nil;
        _appId = nil;
        _base64Encoded = YES;
        _dataCollection = YES;
        _sessionContext = NO;
        _applicationContext = NO;
        _lifecycleEvents = NO;
        _autotrackScreenViews = NO;
        _foregroundTimeout = 600;
        _backgroundTimeout = 300;
        _checkInterval = 15;
        _builderFinished = NO;
        self.previousScreenState = nil;
        self.currentScreenState = nil;
        _exceptionEvents = NO;
#if SNOWPLOW_TARGET_IOS
        _platformContextSchema = kSPMobileContextSchema;
#else
        _platformContextSchema = kSPDesktopContextSchema;
#endif
    }
    return self;
}

- (void) setup {
    [SPUtilities checkArgument:(_emitter != nil) withMessage:@"Emitter cannot be nil."];

    [self setTrackerData];
    if (_sessionContext) {
        _session = [[SPSession alloc] initWithForegroundTimeout:_foregroundTimeout
                                           andBackgroundTimeout:_backgroundTimeout
                                               andCheckInterval:_checkInterval
                                                     andTracker:self];
    }

    if (_autotrackScreenViews) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(receiveScreenViewNotification:)
                                                     name:@"SPScreenViewDidAppear"
                                                   object:nil];
    }
    
    if (_exceptionEvents) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleExceptionNotification:)
                                                     name:@"SPExceptionOccurred"
                                                   object:self];
        NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    }

    _builderFinished = YES;
}

- (void) checkInstall {
    SPInstallTracker * installTracker = [[SPInstallTracker alloc] init];
    if ([installTracker isNewInstall]) {
        SPSelfDescribingJson * installEvent = [[SPSelfDescribingJson alloc] initWithSchema:kSPApplicationInstallSchema andData:@{}];
        SPUnstructured * event = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
            [builder setEventData:installEvent];
        }];
        [self trackUnstructuredEvent:event];
    }
}

- (void) setTrackerData {
    _trackerData = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    kSPVersion, kSPTrackerVersion,
                    _trackerNamespace != nil ? _trackerNamespace : [NSNull null], kSPNamespace,
                    _appId != nil ? _appId : [NSNull null], kSPAppId, nil];
}

// Required

- (void) setEmitter:(SPEmitter *)emitter {
    if (emitter != nil) {
        _emitter = emitter;
    }
}

- (void) setSubject:(SPSubject *)subject {
    _subject = subject;
}

- (void) setBase64Encoded:(BOOL)encoded {
    _base64Encoded = encoded;
}

- (void) setAppId:(NSString *)appId {
    _appId = appId;
    if (_builderFinished && _trackerData != nil) {
        [self setTrackerData];
    }
}

- (void) setTrackerNamespace:(NSString *)trackerNamespace {
    _trackerNamespace = trackerNamespace;
    if (_builderFinished && _trackerData != nil) {
        [self setTrackerData];
    }
}

- (void) setSessionContext:(BOOL)sessionContext {
    _sessionContext = sessionContext;
    if (_session != nil && !sessionContext) {
        [_session stopChecker];
        _session = nil;
    } else if (_builderFinished && _session == nil && sessionContext) {
        _session = [[SPSession alloc] initWithForegroundTimeout:_foregroundTimeout andBackgroundTimeout:_backgroundTimeout andCheckInterval:_checkInterval andTracker:self];
    }
}

- (void) setApplicationContext:(BOOL)applicationContext {
    _applicationContext = applicationContext;
}

- (void) setAutotrackScreenViews:(BOOL)autotrackScreenViews {
    _autotrackScreenViews = autotrackScreenViews;
}

- (void) setForegroundTimeout:(NSInteger)foregroundTimeout {
    _foregroundTimeout = foregroundTimeout;
    if (_builderFinished && _session != nil) {
        [_session setForegroundTimeout:foregroundTimeout];
    }
}

- (void) setBackgroundTimeout:(NSInteger)backgroundTimeout {
    _backgroundTimeout = backgroundTimeout;
    if (_builderFinished && _session != nil) {
        [_session setBackgroundTimeout:backgroundTimeout];
    }
}

- (void) setCheckInterval:(NSInteger)checkInterval {
    _checkInterval = checkInterval;
    if (_builderFinished && _session != nil) {
        [_session setCheckInterval:checkInterval];
    }
}

- (void) setLifecycleEvents:(BOOL)lifecycleEvents {
    _lifecycleEvents = lifecycleEvents;
}

- (void) setExceptionEvents:(BOOL)exceptionEvents {
    _exceptionEvents = exceptionEvents;
}

// Extra Functions

- (void) pauseEventTracking {
    _dataCollection = NO;
    [_emitter stopTimerFlush];
    [_session stopChecker];
}

- (void) resumeEventTracking {
    _dataCollection = YES;
    [_emitter startTimerFlush];
    [_session startChecker];
}

// Getters

- (NSInteger) getSessionIndex {
    return [_session getSessionIndex];
}

- (BOOL) getInBackground {
    return [_session getInBackground];
}

- (BOOL) getIsTracking {
    return _dataCollection;
}

- (NSString*) getSessionUserId {
    return [_session getUserId];
}

- (BOOL) getLifecycleEvents {
    return _lifecycleEvents;
}

- (SPPayload*) getApplicationInfo {
    SPPayload * applicationInfo = [[SPPayload alloc] init];
    NSString * version = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
    NSString * build = [[NSBundle mainBundle] objectForInfoDictionaryKey: (NSString *)kCFBundleVersionKey];
    [applicationInfo addValueToPayload:build forKey:kSPApplicationBuild];
    [applicationInfo addValueToPayload:version forKey:kSPApplicationVersion];
    return applicationInfo;
}

- (void) handleExceptionNotification:(NSNotification *)notification {
    NSDictionary * userInfo = [notification userInfo];
    NSString * stackTrace = [userInfo objectForKey:@"stackTrace"];
    NSString * message = [userInfo objectForKey:@"message"];
    if (message == nil || [message length] == 0) {
        return;
    }
    SPError * error = [SPError build:^(id<SPErrorBuilder> builder) {
        [builder setMessage:message];
        if (stackTrace != nil && [stackTrace length] > 0) {
            [builder setStackTrace:stackTrace];
        }
    }];
    [self trackErrorEvent:error];
}

- (void) receiveScreenViewNotification:(NSNotification *)notification {
    NSString * name = [[notification userInfo] objectForKey:@"viewControllerName"];
    NSString * type = stringWithSPScreenType([[[notification userInfo] objectForKey:@"type"] integerValue]);
    NSString * topViewControllerClassName = [[notification userInfo] objectForKey:@"topViewControllerClassName"];
    NSString * viewControllerClassName = [[notification userInfo] objectForKey:@"viewControllerClassName"];
    SPScreenState * newScreenState = [[SPScreenState alloc] initWithName:name type:type screenId:nil transitionType:nil];
    [self populatePreviousScreenState];
    [self setCurrentScreenState:newScreenState];
    SPScreenView *event = [SPScreenView build:^(id<SPScreenViewBuilder> builder) {
        if (self.previousScreenState) {
            [builder setWithPreviousState:self.previousScreenState];
        }
        if (self.currentScreenState) {
            [builder setWithCurrentState:self.currentScreenState];
        }
        [builder setTopViewControllerName:topViewControllerClassName];
        [builder setViewControllerName:viewControllerClassName];
    }];
    [self trackScreenViewEvent:event];
}

- (void) populatePreviousScreenState {
    // Covers case if tracker initializes and doesn't set state
    // (not sure if this is true, but worth covering against)
    if (self.currentScreenState) {
        self.previousScreenState = self.currentScreenState;
    }
}

// Event Tracking Functions

- (void) trackPageViewEvent:(SPPageView *)event {
    if (!_dataCollection) {
        return;
    }
    [self addEventWithPayload:[event getPayload] andContext:[event getContexts] andEventId:[event getEventId]];
}

- (void) trackStructuredEvent:(SPStructured *)event {
    if (!_dataCollection) {
        return;
    }
    [self addEventWithPayload:[event getPayload] andContext:[event getContexts] andEventId:[event getEventId]];
}

- (void) trackUnstructuredEvent:(SPUnstructured *)event {
    if (!_dataCollection) {
        return;
    }
    [self addEventWithPayload:[event getPayloadWithEncoding:_base64Encoded] andContext:[event getContexts] andEventId:[event getEventId]];
}

- (void) trackSelfDescribingEvent:(SPSelfDescribingJson *)event {
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData: event];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackScreenViewEvent:(SPScreenView *)event {
    //newScreenViewState:(SPScreenViewState *)newState;
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event getContexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackTimingEvent:(SPTiming *)event {
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event getContexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackEcommerceEvent:(SPEcommerce *)event {
    if (!_dataCollection) {
        return;
    }
    [self addEventWithPayload:[event getPayload] andContext:[event getContexts] andEventId:[event getEventId]];

    NSNumber *tstamp = [event getTimestamp];
    for (SPEcommerceItem * item in [event getItems]) {
        [item setTimestamp:tstamp];
        [self trackEcommerceItemEvent:item];
    }
}

- (void) trackEcommerceItemEvent:(SPEcommerceItem *)event {
    [self addEventWithPayload:[event getPayload] andContext:[event getContexts] andEventId:[event getEventId]];
}

- (void) trackConsentWithdrawnEvent:(SPConsentWithdrawn *)event {
    NSArray * documents = [event getDocuments];
    NSMutableArray * contexts = [event getContexts];
    [contexts addObjectsFromArray:documents];

    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event contexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackConsentGrantedEvent:(SPConsentGranted *)event {
    NSArray * documents = [event getDocuments];
    NSMutableArray * contexts = [event getContexts];
    [contexts addObjectsFromArray:documents];
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event contexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackPushNotificationEvent:(SPPushNotification *)event {
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event getContexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackForegroundEvent:(SPForeground *)event {
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event getContexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackBackgroundEvent:(SPBackground *)event {
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event getContexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

- (void) trackErrorEvent:(SPError *)event {
    SPUnstructured * unstruct = [SPUnstructured build:^(id<SPUnstructuredBuilder> builder) {
        [builder setEventData:[event getPayload]];
        [builder setTimestamp:[event getTimestamp]];
        [builder setContexts:[event getContexts]];
        [builder setEventId:[event getEventId]];
    }];
    [self trackUnstructuredEvent:unstruct];
}

// Event Decoration

- (void) addEventWithPayload:(SPPayload *)pb andContext:(NSMutableArray *)contextArray andEventId:(NSString *)eventId {
    [_emitter addPayloadToBuffer:[self getFinalPayloadWithPayload:pb andContext:contextArray andEventId:eventId]];
}

- (SPPayload *) getFinalPayloadWithPayload:(SPPayload *)pb andContext:(NSMutableArray *)contextArray andEventId:(NSString *)eventId {
    [pb addDictionaryToPayload:_trackerData];

    // Add Subject information
    if (_subject != nil) {
        [pb addDictionaryToPayload:[[_subject getStandardDict] getAsDictionary]];
    } else {
        [pb addValueToPayload:[SPUtilities getPlatform] forKey:kSPPlatform];
    }

    // Add the contexts
    SPSelfDescribingJson * context = [self getFinalContextWithContexts:contextArray andEventId:eventId];
    if (context != nil) {
        [pb addDictionaryToPayload:[context getAsDictionary]
                     base64Encoded:_base64Encoded
                   typeWhenEncoded:kSPContextEncoded
                typeWhenNotEncoded:kSPContext];
    }

    return pb;
}

- (SPSelfDescribingJson *) getFinalContextWithContexts:(NSMutableArray *)contextArray andEventId:(NSString *)eventId {
    SPSelfDescribingJson * finalContext = nil;

    // Add contexts if populated
    if (_subject != nil) {
        NSDictionary * platformDict = [[_subject getPlatformDict] getAsDictionary];
        if (platformDict != nil) {
            [contextArray addObject:[[SPSelfDescribingJson alloc] initWithSchema:_platformContextSchema andData:platformDict]];
        }
        NSDictionary * geoLocationDict = [_subject getGeoLocationDict];
        if (geoLocationDict != nil) {
            [contextArray addObject:[[SPSelfDescribingJson alloc] initWithSchema:kSPGeoContextSchema andData:geoLocationDict]];
        }
    }

    if (_applicationContext) {
        NSDictionary * applicationDict = [[self getApplicationInfo] getAsDictionary];
        if (applicationDict != nil) {
            [contextArray addObject:[[SPSelfDescribingJson alloc] initWithSchema:kSPApplicationContextSchema andData:applicationDict]];
        }
    }

    // Add session if active
    if (_session != nil) {
        NSDictionary * sessionDict = [_session getSessionDictWithEventId:eventId];
        if (sessionDict != nil) {
            [contextArray addObject:[[SPSelfDescribingJson alloc] initWithSchema:kSPSessionContextSchema andData:sessionDict]];
        }
    }

    // If some contexts are available...
    if (contextArray.count > 0) {
        NSMutableArray * contexts = [[NSMutableArray alloc] init];
        for (SPSelfDescribingJson * context in contextArray) {
            [contexts addObject:[context getAsDictionary]];
        }
        finalContext = [[SPSelfDescribingJson alloc] initWithSchema:kSPContextSchema andData:contexts];
    }
    return finalContext;
}

@end

