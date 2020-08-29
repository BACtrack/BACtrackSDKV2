//
//  BacTrac2SerialProtocol.m
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 2/28/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import "BacTrac2SerialProtocol.h"
#import "NSMutableData+AppendHex.h"


@interface BacTrac2SerialProtocol ()
@property (nonatomic, copy)   NSMutableData *buffer;
@end

@implementation BacTrac2SerialProtocol

-(id)init
{
    if (self = [super init]) {
        // Initialized
        _buffer = [NSMutableData dataWithCapacity:16];
    }
    return self;
}

-(NSData *)generateDeviceIdRequest
{
    return [[[BacTrac2Message alloc] initWithCommand:BT2CommandDeviceIDRequest data:nil] packet];
}

-(NSData *)generateStatusReportRequest
{
    return [[[BacTrac2Message alloc] initWithCommand:BT2CommandStatusReportRequest data:nil] packet];
}

-(NSData *)generateLastErrorReportRequest
{
    return [[[BacTrac2Message alloc] initWithCommand:BT2CommandErrorReportRequest data:nil] packet];
}

-(NSData *)generateSettingReadRequest:(BT2SettingParamId)paramId
{
    NSData *data = [NSData dataWithBytes:&paramId length:sizeof(paramId)];
    
    BacTrac2Message *message = [[BacTrac2Message alloc] initWithCommand:BT2CommandSettingReadRequest data:data];
    return [message packet];
}

-(NSData *)generateSettingWriteRequest:(BT2SettingParamId)paramId value:(NSData *)data
{
    //XXX currently don't do sanity checking to make sure param is writable
    //Need to also check the data is of the right size.
    BacTrac2Message *message = [[BacTrac2Message alloc] initWithCommand:BT2CommandSettingReadRequest data:data];
    return [message packet];
}

-(NSData *)generateDeviceControlRequest:(BT2DeviceControlCommand)cc
{
    NSData *data = [NSData dataWithBytes:&cc length:sizeof(cc)];
    BacTrac2Message *message = [[BacTrac2Message alloc] initWithCommand:BT2CommandDeviceControlRequest data:data];
    return [message packet];
}


-(BacTrac2Message *)processNewPacket:(NSData *)packet
{
    //we might be getting partials so add to buffer, then introspect.
    [_buffer appendData:packet];
    
    if (_buffer.length < 2) {
        return NULL;
    }
    
    //extract start and end ranges for frame.
    NSRange range = NSMakeRange(0, [_buffer length]);
    NSRange startRange = [_buffer rangeOfData:[BacTrac2Message sop] options:0 range:range];
    NSRange endRange = [_buffer rangeOfData:[BacTrac2Message eop] options:NSDataSearchBackwards range:range];
    
    if (endRange.location == NSNotFound) {
        return NULL;
    }

    if (startRange.location == NSNotFound) {
        [_buffer setLength:0];
        return NULL;
    }
    
    //By this point there should be a start and end to a message in the buffer. We now validate that the message length checks out.
    UInt8 payloadLength;
    //Double check that there our expected length byte isnt out of bounds
    if([_buffer length] <= startRange.location + startRange.length){
        //Wipe potential residue in the front of the buffer up until the end sequence
        [_buffer replaceBytesInRange:NSMakeRange(0, endRange.location + endRange.length) withBytes:NULL length:0];
        return NULL;
    }
    //Get length of Command ID and data
    [_buffer getBytes:&payloadLength range:NSMakeRange(startRange.location + startRange.length, 1)];
    
    //Check that this message is the correct length
    if ((startRange.location + 3 + payloadLength + 1) != endRange.location ) {
        //Wipe potential residue in the front of the buffer and the frameData
        [_buffer replaceBytesInRange:NSMakeRange(0, endRange.location + endRange.length) withBytes:NULL length:0];
        return NULL;
    }
    
    //Grab useable frame.
    NSData *frameData = [_buffer subdataWithRange:NSMakeRange(startRange.location, endRange.location + endRange.length - startRange.location)];
    //Wipe potential residue in the front of the buffer and the frameData
    [_buffer replaceBytesInRange:NSMakeRange(0, endRange.location + endRange.length) withBytes:NULL length:0];

    BacTrac2Message *message = [[BacTrac2Message alloc] initWithPacket:frameData];
    if (message && [message isValid])
    {
        return message;
    }
    return NULL;
}

@end
