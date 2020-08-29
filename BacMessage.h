//
//  BacMessage.h
//  BacTrackManagement
//
//  Created by Raymond Kampmeier on 1/9/13.
//  Copyright (c) 2013 Punch Through Design. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BacMessage : NSObject

@property (nonatomic) UInt8 command;
@property (nonatomic, copy) NSData* data;
@property (nonatomic) UInt8 checksum;
@property (nonatomic) BOOL haschecksum;
@property (nonatomic) BOOL checksumisvalid;


+(BOOL)parseMessage:(NSData*)unparsed_data intoBacMessage:(BacMessage*)bac_message_object;
+(BOOL)compileMessage:(NSData**)compiled_message_data fromBacMessage:(BacMessage*)bac_message_object;

+(BOOL)validateChecksum:(BacMessage*)bac_message_object;
+(BOOL)generateChecksum:(BacMessage*)bac_message_object;


@end
