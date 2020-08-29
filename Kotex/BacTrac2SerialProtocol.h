//
//  BacTrac2SerialProtocol.h
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 2/28/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BacTrac2Message.h"

@interface BacTrac2SerialProtocol : NSObject


-(BacTrac2Message *)processNewPacket:(NSData *)packet;

-(NSData *)generateDeviceIdRequest;
-(NSData *)generateStatusReportRequest;
-(NSData *)generateLastErrorReportRequest;
-(NSData *)generateSettingReadRequest:(BT2SettingParamId)paramId;
-(NSData *)generateSettingWriteRequest:(BT2SettingParamId)paramId value:(NSData *)data;
-(NSData *)generateDeviceControlRequest:(BT2DeviceControlCommand)cc;

@end
