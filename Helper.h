//
//  Helper.h
//  BacTrack_Demo
//
//  Created by KJ on 9/11/12.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface Helper : NSObject

+(NSString *) UUIDToNSString:(CFUUIDRef) UUID;
+(NSString *)CBUUIDToString:(CBUUID *)uuid;

+(int) compareCBUUID:(CBUUID *) UUID1 UUID2:(CBUUID *)UUID2;

+(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service;

@end
