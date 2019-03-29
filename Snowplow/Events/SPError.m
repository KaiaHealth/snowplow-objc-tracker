//
//  SPException.m
//  Snowplow-iOS
//
//  Created by Michael Hadam on 3/28/19.
//  Copyright © 2019 Snowplow Analytics. All rights reserved.
//

#import "SPError.h"

@implementation SPError {
    NSString * _name;
    NSString * _stackTrace;
    NSString * _message;
}

+ (instancetype) build:(void(^)(id<SPErrorBuilder>builder))buildBlock {
    SPError * event = [SPError new];
    if (buildBlock) { buildBlock(event); }
    [event preconditions];
    return event;
}

- (id) init {
    self = [super init];
    return self;
}

- (void) preconditions {
    [SPUtilities checkArgument:(_message != nil) withMessage:@"Message cannot be nil or empty."];
    [self basePreconditions];
}

// --- Builder Methods

- (void) setMessage:(NSString *)message {
    _message = message;
}

- (void) setStackTrace:(NSString *)stackTrace {
    _stackTrace = stackTrace;
}

- (void) setName:(NSString *)name {
    _name = name;
}

// --- Public Methods

- (SPSelfDescribingJson *) getPayload {
    SPPayload * event = [[SPPayload alloc] init];
    [event addValueToPayload:_message forKey:kSPErrorMessage];
    [event addValueToPayload:_stackTrace forKey:kSPErrorStackTrace];
    [event addValueToPayload:_name forKey:kSPErrorName];
    [event addValueToPayload:@"OBJECTIVEC" forKey:kSPErrorLanguage];

    return [[SPSelfDescribingJson alloc] initWithSchema:kSPErrorSchema andData:event];
}

@end
