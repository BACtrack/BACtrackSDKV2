//
//  BacTrackAPI_Kotex.h
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/9/14.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BacTrackAPIDelegate.h"
#import "BACDeviceInteractionProtocol.h"


@interface BacTrackAPI_Vio : NSObject <BACDeviceInteractionProtocol>

// Callback delegate. Must be set
@property (strong, nonatomic) id<BacTrackAPIDelegate> delegate;

// Initialize class with this method
-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral;

-(void)configurePeripheral;

@end
