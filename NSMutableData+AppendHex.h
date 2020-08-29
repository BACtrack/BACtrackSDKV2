//
//  NSMutableData+AppendHex.h
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/8/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableData (NSMutableData_AppendHex)

+ (NSMutableData *)dataFromHexString:(NSString *)string;
- (void)appendHexString:(NSString *)string;

@end

