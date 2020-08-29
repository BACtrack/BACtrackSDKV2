//
//  NSMutableData+AppendHex.m
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/8/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//


#import "NSMutableData+AppendHex.h"

@implementation NSMutableData (NSMutableData_AppendHex)

+ (NSMutableData *)dataFromHexString:(NSString *)string
{
    NSMutableData *data= [NSMutableData new];

    [data appendHexString:string];
    return data;
}

- (void)appendHexString:(NSString *)string
{
    string = [string lowercaseString];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    int i = 0;
    int length = (int)string.length;
    while (i < length-1) {
        char c = [string characterAtIndex:i++];
        if (c < '0' || (c > '9' && c < 'a') || c > 'f')
            continue;
        byte_chars[0] = c;
        byte_chars[1] = [string characterAtIndex:i++];
        whole_byte = strtol(byte_chars, NULL, 16);
        [self appendBytes:&whole_byte length:1];
    }
}
@end
