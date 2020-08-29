//
//  BacTrackAPI_C6.h
//  BacTrackManagement
//
//  Created by Daniel Walton on 8/10/17
//  Copyright (c) 2017 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BacTrackAPIDelegate.h"
#import "BACDeviceInteractionProtocol.h"


@interface BacTrackAPI_C6 : NSObject <BACDeviceInteractionProtocol>

// Callback delegate. Must be set
@property (strong, nonatomic) id<BacTrackAPIDelegate> delegate;
@property (nonatomic) BACtrackDeviceType type;

// Initialize class with this method
-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral;

-(void)configurePeripheral;

-(void)writeUnitsToDevice:(BACtrackUnit)units;
-(void)readUnitsFromDevice;

@end
