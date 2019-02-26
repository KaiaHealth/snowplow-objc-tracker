//
//  SPScreenViewState.m
//  Snowplow
//
//  Copyright (c) 2019 Snowplow Analytics Ltd. All rights reserved.
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
//  Authors: Michael Hadam
//  Copyright: Copyright (c) 2019 Snowplow Analytics Ltd
//  License: Apache License Version 2.0
//

#import <Foundation/Foundation.h>
#import "SPScreenState.h"
#import "Snowplow.h"
#import "SPUtilities.h"

@implementation SPScreenState

- (id) init {
    return [self initWithName:nil type:nil screenId:nil transitionType:nil];
}

- (id) initWithName:theName type:theType screenId:theScreenId transitionType:theTransitionType {
    if (self = [super init]) {
        _name = theName;
        _screenId = theScreenId;
        _type = theType;
        _transitionType = theTransitionType;
        return self;
    }
    return nil;
}

- (id) initWithName:theName type:theType screenId:theScreenId {
    return [self initWithName:theName type:theType screenId:theScreenId transitionType:nil];
}

/**- (id) initWithScreenView:(SPScreenView *)screenView {
    return [self initWithName:[screenView _name] uuid:<#(id)#> type:<#(id)#> transitionType:<#(id)#>];
}*/

- (id)copyWithZone:(NSZone *)zone
{
    SPScreenState * state = [[[self class] allocWithZone:zone] init];
    return [state initWithName:self.name
                          type:self.type
                    screenId:self.screenId
                transitionType:self.transitionType];
}

- (BOOL) isValid {
    return ([SPUtilities validateString:self.name] != nil);
}

- (NSDictionary *) getValidDictionary {
    if (![self isValid]) {
        return nil;
    }

    NSMutableDictionary * validDictionary = [[NSMutableDictionary alloc] init];
    [validDictionary setValue:self.name forKey:kSPSvName];
    [validDictionary setValue:[SPUtilities validateString:self.screenId] forKey:kSPSvScreenId];
    [validDictionary setValue:[SPUtilities validateString:self.type] forKey:kSPSvType];
    [validDictionary setValue:[SPUtilities validateString:self.transitionType] forKey:kSPSvTransitionType];

    return [[NSDictionary alloc] initWithDictionary:validDictionary];
}

@end
