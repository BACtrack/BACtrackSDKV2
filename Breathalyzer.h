//
//  Breathalyzer.h
//  BacTrackManagement
//
//  Created by Kevin Johnson, Punch Through Design on 10/31/12.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "Globals.h"

@interface Breathalyzer : NSObject

@property (strong, nonatomic) NSString * uuid;
@property (strong, nonatomic) NSNumber * rssi;
@property (strong, nonatomic) NSString * serial;
@property (strong, nonatomic) CBPeripheral * peripheral;
@property (nonatomic) NSInteger firmwareVersion;
@property (nonatomic) BACtrackDeviceType type;

@end
