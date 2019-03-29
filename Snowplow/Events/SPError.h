//
//  SPException.h
//  Snowplow-iOS
//
//  Created by Michael Hadam on 3/28/19.
//  Copyright © 2019 Snowplow Analytics. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Snowplow.h"
#import "SPEvent.h"
#import "SPSelfDescribingJson.h"
#import "SPPayload.h"
#import "SPUtilities.h"

@class SPEvent;
@class SPPayload;

#pragma mark - Error event builder

/*!
 @protocol SPErrorBuilder
 @brief The protocol for building error events.
 */
@protocol SPErrorBuilder <SPEventBuilder>

/*!
 @brief Set the error message.
 
 @param message The error message.
 */
- (void) setMessage:(NSString *)message;

/*!
 @brief Set the exception stack trace.
 
 @param stackTrace The stack trace of the exception.
 */
- (void) setStackTrace:(NSString *)stackTrace;

/*!
 @brief Set the exception name.
 
 @param name The exception name.
 */
- (void) setName:(NSString *)name;

@end

#pragma mark - Error event

/*!
 @class SPError
 @brief An error event.
 */
@interface SPError : SPEvent <SPErrorBuilder>
+ (instancetype) build:(void(^)(id<SPErrorBuilder>builder))buildBlock;
- (SPSelfDescribingJson *) getPayload;
@end
