//
//  BacTrac2Message.m
//  BacTrackManagement
//
//  Created by Nick Lane-Smith on 2/28/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import "BacTrac2Message.h"
#import "Globals.h"
#import "NSMutableData+AppendHex.h"

@interface BacTrac2Message () {
    NSData *payload;
    NSString *errorString;
    StatusReportResponse srr;
    DeviceIdResponse  dir;
    ErrorReportResponse err;
    SettingReportResponse setrr;
    BOOL validChecksum;
}

@end



@implementation BacTrac2Message


#pragma mark -
#pragma mark Public Methods
/****************************************************************************/
/*								Public Methods                             */
/****************************************************************************/

- (id) initWithCommand:(BT2Command)cmd data:(NSData *)data
{
    if (self = [super init]) {
        validChecksum = NO;
        _command = cmd;
        payload = data;
    }
    return self;
}

- (id) initWithPacket:(NSData *)data
{
    if (self = [super init]) {
        validChecksum = NO;
        [self parsePacket:data];
    }
    return self;
}

- (BOOL)isValid
{
    return validChecksum && !errorString;
}

- (ErrorReportResponse)errorReportResponse
{
    return err;
}

- (DeviceIdResponse)deviceIdResponse
{
    return dir;
}


- (StatusReportResponse)statusReportResponse
{
    return srr;
}

- (SettingReportResponse)settingReportResponse
{
    return  setrr;
}


-(void)parseStatusReport
{
    //extract Activity State and Battery State
    NSRange stateRange = {0, 1};
    [payload getBytes:&srr.battery_level range:stateRange];
    
    //Battery Level [7:4]
    srr.activity_state = srr.battery_level;
    srr.battery_level >>= 4;
    //Activity State [3:0]
    srr.activity_state &=0x0f;
    
    NSRange heatRange = {1, 1};
    [payload getBytes:&srr.heat_count range:heatRange];
    
    NSRange bacRange = {2, 2};
    Byte bac[bacRange.length];
    [payload getBytes:&bac range:bacRange];
    
    //BAC Reading LSB (byte6) MSB (byte7) -- bit fiddle to reorder.
    srr.bac_reading = bac[1];
    srr.bac_reading <<= 8;
    srr.bac_reading |= bac[0];
    
    NSLog(@"activity_state, battery, heat_count, BAC (%d, %d, %d, %d)", srr.activity_state, srr.battery_level, srr.heat_count, srr.bac_reading);
}


-(void)parseDeviceID
{
    //extract four bytes all in a row.
    NSRange range = {0, 1};
    [payload getBytes:&dir.hardware_id range:range];
    range.location++;
    [payload getBytes:&dir.hardware_version range:range];
    range.location++;
    [payload getBytes:&dir.software_id range:range];
    range.location++;
    [payload getBytes:&dir.software_version range:range];
    
    NSLog(@"hw_id/ver, hw_id/ver (%d, %d, %d, %d)", dir.hardware_id, dir.hardware_version, dir.software_id, dir.software_version);
}

-(void)parseErrorReport
{
    //check length
    NSRange range = {0, 1};
    //extract error code
    [payload getBytes:&err.error_code range:range];
    
    //optionally extract info field
    if ([payload length] > 1) {
        range.location++;
        [payload getBytes:&err.error_info range:range];
    }
    NSLog(@"code,info (%d, %d)", err.error_code, err.error_info);
}

-(void)parseSettingRead
{
    
    //extract paramater ID and Status
    NSRange range = {0, 1};
    [payload getBytes:&setrr.param_id range:range];
    range.location++;
    [payload getBytes:&setrr.status range:range];
    
    NSLog(@"param_id,status (%d, %d)", setrr.param_id, setrr.status);
    
    //read in data only on success.
    if (setrr.status == BT2SettingStatusSuccess) {
        //Note: ignoring LEDs for now.
        NSRange dataRange = {2, 1};
        if(setrr.param_id == BT2SettingUseCount) {
            dataRange.length++;
        }
        //Note: if this becomes bigger than 2 bytes, the struct will need to be changed.
        [payload getBytes:&setrr.data range:dataRange];
        NSLog(@"data (%hu)", setrr.data);
    }
}

-(void)parseSettingWrite
{
    NSRange range = {0, 1};
    [payload getBytes:&setrr.param_id range:range];
    range.location++;
    [payload getBytes:&setrr.status range:range];
    
    NSLog(@"param_id, status (%d, %d)", setrr.param_id, setrr.status);
}

-(void)parseSettingChangeReport
{
    //Note: Spec only seems to support this response for on Button Status
    
    NSRange range = {0, 1};
    [payload getBytes:&setrr.param_id range:range];
    
    NSRange dataRange = {1, 1};
    [payload getBytes:&setrr.status range:dataRange];
    NSLog(@"param_id, button_status (%d, %d)", setrr.param_id, setrr.status);
}

-(void)parseDeviceControl
{
    NSRange range = {0, 1};
    [payload getBytes:&setrr.param_id range:range];
    range.location++;
    [payload getBytes:&setrr.status range:range];
    
    NSLog(@"cc,status (%d, %d)", setrr.param_id, setrr.status);
}

-(BOOL)parsePayload
{
    //sanity check our payload.
    if (!payload || [payload length] == 0) {
        return NO;
    }
        
    switch (_command) {
        case BT2CommandDeviceIDResponse:
        {
            [self parseDeviceID];
        }
            break;
        case BT2CommandStatusReportResponse:
        {
            [self parseStatusReport];
        }
            break;
        case BT2CommandErrorReportResponse:
        {
            [self parseErrorReport];
        }
            break;
        case BT2CommandSettingReadResponse:
        {
            [self parseSettingRead];
        }
            break;
        case BT2CommandSettingWriteResponse:
        {
            [self parseSettingWrite];
        }
            break;
        case BT2CommandSettingChangeReportResponse:
        {
            [self parseSettingChangeReport];
        }
            break;
        case BT2CommandDeviceControlResponse:
        {
            [self parseDeviceControl];
        }
            break;
            //We should only be parsing responses, these are here to catch requests.
        case BT2CommandDeviceIDRequest:
        case BT2CommandStatusReportRequest:
        case BT2CommandErrorReportRequest:
        case BT2CommandSettingReadRequest:
        case BT2CommandSettingWriteRequest:
        case BT2CommandDeviceControlRequest:
            //handle this error
            errorString = @"Tried parsing payload for a request";
            NSLog(@"Error: %@", errorString);
            return NO;
            break;
    }
    
    return YES;
}

//XXX make these static and wrap?
+(NSData *)sop
{
    return [NSMutableData dataFromHexString:@"1002"];
}

+(NSData *)eop
{
    return [NSMutableData dataFromHexString:@"1017"];
}

-(BOOL)parsePacket:(NSData *)data
{
    //NSLog(@"ParsePacket: %@", data);
    validChecksum = NO;
    NSData *sop = [BacTrac2Message sop];
    NSData *eop = [BacTrac2Message eop];
    
    @try {
        //Sanity check the packet -- start.
        NSRange sopRange = NSMakeRange(0, [sop length]);
        NSData *sopData = [data subdataWithRange:sopRange];
        if (![sopData isEqualToData:sop]) {
            errorString = @"missing SOP";
            return NO;
        }
        
        // extract the packet length:
        NSRange lengthRange = NSMakeRange(NSMaxRange(sopRange),1);
        NSData *lengthData = [data subdataWithRange:lengthRange];
        uint8_t length;
        [lengthData getBytes:&length length:sizeof(length)];
        
        //extract the packet command:
        NSRange commandRange = NSMakeRange(NSMaxRange(lengthRange),1);
        NSData *commandData = [data subdataWithRange:commandRange];
        uint8_t cmd;
        [commandData getBytes:&cmd length:sizeof(cmd)];
        
        //XXX check command is valid? -- weak enums...
        _command = cmd;
  //      NSLog(@"command: %02x", (uint8_t)cmd);
        
        //extract the packet payload:
        NSRange payloadRange = commandRange;
        if (length > 1) {
            payloadRange = NSMakeRange(NSMaxRange(commandRange),length - 1);
            NSData *payloadData = [data subdataWithRange:payloadRange];
            payload = payloadData;
            //NSLog(@"payload: %@", payloadData);
        }
        
        //extract the checksum:
        //Note: payloadRange will be == command range if we have no payload
        NSRange checksumRange = NSMakeRange(NSMaxRange(payloadRange),1);
        NSData *checksumData = [data subdataWithRange:checksumRange];
        uint8_t checksum;
        [checksumData getBytes:&checksum length:sizeof(checksum)];
        
        if (![self validateChecksum:checksum]) {
            errorString = @"checksum invalid";
            NSLog(@"parsePacket: %@", errorString);
            return NO;
        }
        validChecksum = YES;
        
        //Sanity check the packet -- end.
        NSRange eopRange = NSMakeRange(NSMaxRange(checksumRange), [eop length]);
        NSData *eopData = [data subdataWithRange:eopRange];
        if (![eopData isEqualToData:eop]) {
            errorString = @"missing EOP";
            return NO;
        }
    }
    @catch (NSException *exception) {
        //Catching so we don't need to worry offset issues or bad access.
        //probably the NSRangeException
        errorString = [exception description];
        validChecksum = NO;
        return NO;
    }
    [self parsePayload];
    return YES;
}

- (NSData *)packet
{
    NSMutableData *packet = [NSMutableData dataWithCapacity:0];
    
    [packet appendData:[BacTrac2Message sop]];
    uint8_t length = [self packet_length];
    [packet appendBytes:&length length:sizeof(length)];
    [packet appendBytes:&_command length:sizeof(_command)];
    
    //append payload if we have one.
    if (length > 1) {
        [packet appendData:payload];
    }
    
    uint8_t csum = [self generateChecksum];
    [packet appendBytes:&csum length:sizeof(csum)];
    [packet appendData:[BacTrac2Message eop]];
    return packet;
}

#pragma mark -
#pragma mark Internal Methods
/****************************************************************************/
/*								Internal Helper Methods                     */
/****************************************************************************/


// calculate don't store
-(uint8_t)packet_length
{
    return (uint8_t) [payload length] + sizeof(BT2Command);
}

- (BOOL)validateChecksum:(uint8_t)checksum
{
    return ([self generateChecksum] == checksum);
}

//assumption: calling this after payload, command, etc... are loaded.
- (uint8_t)generateChecksum
{
    uint8_t checksum = [self packet_length] ^ self.command;
    Byte *dataBuffer = (Byte *)[payload bytes];
    for(int i = 0; i < [payload length] ; i ++) {
        checksum ^= dataBuffer[i];
    }
    return checksum;
}

@end
