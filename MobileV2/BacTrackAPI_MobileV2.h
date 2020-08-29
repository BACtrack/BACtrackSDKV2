//
//  BacTrackAPI_MobileV2.h
//  BacTrackManagement
//
//  Created by Louis Gorenfeld on 9/24/19
//  Copyright (c) 2019 KHN Solutions LLC. All rights reserved.
//
// Based on the C6/C8 module

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BacTrackAPIDelegate.h"
#import "BACDeviceInteractionProtocol.h"


@interface BacTrackAPI_MobileV2 : NSObject <BACDeviceInteractionProtocol>

// Callback delegate. Must be set
@property (strong, nonatomic) id<BacTrackAPIDelegate> delegate;
@property (nonatomic) BACtrackDeviceType type;

// Initialize class with this method
-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral;

-(void)configurePeripheral;

-(void)writeUnitsToDevice:(BACtrackUnit)units;

@end
