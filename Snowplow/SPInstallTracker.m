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

#import "SPInstallTracker.h"
#import "Snowplow.h"

@implementation SPInstallTracker

- (id) init {
    if (self = [super init]) {
        NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
        if ([userDefaults boolForKey:kSPInstalledBeforeKey]) {
            // if the value has been set in userDefaults before, the tracker has been used before
            self.isNewInstall = @NO;
        } else {
            // mark the install if there's no value in userDefaults
            [userDefaults setBool:YES forKey:kSPInstalledBeforeKey];
            // since the value was missing in userDefaults, we're assuming this is a new install
            self.isNewInstall = @YES;
        }
        return self;
    }
    return nil;
}

@end
