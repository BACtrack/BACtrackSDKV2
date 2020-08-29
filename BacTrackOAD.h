//
//  BacTrackOAD.h
//  BacTrackManagement
//
//  Created by Kevin Johnson, Punch Through Design on 3/6/13.
//  Copyright (c) 2013 Punch Through Design. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "oad.h"
#import "BLEDevice.h"
#import "BacTrackAPI.h"

@interface BacTrackOAD : NSObject

@property (strong, nonatomic) id<BacTrackAPIDelegate> delegate;

-(void)updateFirmwareForDevice:(BLEDevice *)dev withImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath;
-(void)cancelFirmware;
-(void)didUpdateValueForProfile:(CBCharacteristic *)characteristic;
-(void)didWriteValueForProfile:(CBCharacteristic *)characteristic error:(NSError *)error;
-(void)deviceDisconnected:(CBPeripheral *)peripheral;

@end
