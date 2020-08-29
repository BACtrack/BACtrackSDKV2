//
//  BacTrackAPI.h
//  BacTrack_Demo
//
//  Created by Kevin Johnson, Punch Through Design on 9/11/12.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BACDeviceMangementProtocol.h"
#import "BACDeviceInteractionProtocol.h"
#import "BacTrackAPIDelegate.h"

@class Breathalyzer;

@interface BacTrackAPI : NSObject <BACDeviceMangementProtocol, BACDeviceInteractionProtocol>

// Callback delegate. Must be set
@property (strong, nonatomic) id<BacTrackAPIDelegate> delegate;

@end
