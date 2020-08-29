//
//  BacMessage.m
//  BacTrackManagement
//
//  Created by Raymond Kampmeier on 1/9/13.
//  Copyright (c) 2013 Punch Through Design. All rights reserved.
//

#import "BacMessage.h"
#import "Globals.h"

@implementation BacMessage

+(BOOL)parseMessage:(NSData*)unparsed_characteristic_data intoBacMessage:(BacMessage*)bac_message_object{
    
    bac_message_object.checksumisvalid = FALSE;
    bac_message_object.haschecksum = FALSE;
    
    UInt8 datalength = 0;
    UInt8 fullmessagedata[MOBILE__COMMAND_RECEIVE_CHARACTERISTIC_SIZE];
    
    //Move characteristic NSData into Byte array
    [unparsed_characteristic_data getBytes:fullmessagedata length:MOBILE__COMMAND_RECEIVE_CHARACTERISTIC_SIZE];

    //If first byte is not Start of Frame byte then return with FALSE
    if(fullmessagedata[0] != MOBILE__SOF)
        return FALSE;
    
    //Read second byte for command type, which determines data size
    bac_message_object.command = fullmessagedata[1];
    switch (fullmessagedata[1]) {
        case MOBILE__COMMAND_RECEIVE_ACK:
            datalength = 0;
            break;
        case MOBILE__COMMAND_RECEIVE_NACK:
            datalength = 0;
            break;
        case MOBILE__COMMAND_RECEIVE_STATUS:
            datalength = MOBILE__COMMAND_RECEIVE_STATUS_DATALENGTH;
            break;
        case MOBILE__COMMAND_RECEIVE_ERROR:
            datalength = MOBILE__COMMAND_RECEIVE_ERROR_DATALENGTH;
            break;
        case MOBILE__COMMAND_RECEIVE_BLOW_SETTING:
            datalength = MOBILE__COMMAND_RECEIVE_BLOW_SETTING_DATALENGTH;
            break;
        case MOBILE__COMMAND_RECEIVE_CALIBRATION_STATUS:
            datalength = MOBILE__COMMAND_RECEIVE_CALIBRATION_STATUS_DATALENGTH;
            break;
        //Removed this error as of Protocol 2_6. This functionality is now included in MOBILE__COMMAND_RECEIVE_ERROR
       /* case MOBILE__COMMAND_RECEIVE_CALIBRATION_ERROR:
            datalength = MOBILE__COMMAND_RECEIVE_CALIBRATION_ERROR_DATALENGTH;
            break;*/  
        case MOBILE__COMMAND_RECEIVE_CALIBRATION_RESULTS:
            datalength = MOBILE__COMMAND_RECEIVE_CALIBRATION_RESULTS_DATALENGTH;
            break;
        
        //If command type is unknown, return FALSE
        default:
            return FALSE;
            break;
    }
    
    //Copy message data into object
    bac_message_object.data = [[NSData alloc] initWithBytes:(fullmessagedata+2) length:datalength];
    
    //Message contains checksum if datalength > 1
    if(datalength > 1)
    {
        if((2+datalength)<20){
            bac_message_object.checksum = fullmessagedata[2+datalength];
            bac_message_object.haschecksum = TRUE;
        }else{
            return FALSE;
        }
    //Message does not contain checksum if datalength == 1    
    }else if(datalength == 1 || datalength == 0){
        bac_message_object.checksum = 0x00;
        bac_message_object.haschecksum = FALSE;
        //Just if case this is check later in the code when not realizing that this type of message has no checksum
        bac_message_object.checksumisvalid = TRUE;
    }
    
    //See if there is space for EOF
    if((3+datalength)<20){
        //If supposed final byte of message does not match EOF, return false
        if(fullmessagedata[3+datalength] != MOBILE__EOF ){
            return FALSE;
        }
    }else{
        return FALSE;
    }
    
    //validate checksum, return FALSE if checksum is incorrect. This could be done external of the parsing function
    if(bac_message_object.haschecksum == TRUE && (bac_message_object.checksumisvalid = [BacMessage validateChecksum:bac_message_object] == FALSE))
        return FALSE;
    
    
    return TRUE;
}

+(BOOL)compileMessage:(NSData**)compiled_message_data fromBacMessage:(BacMessage*)bac_message_object{
    //check for valid message format
    if(bac_message_object.command == 0x00 || bac_message_object.data == NULL)
        return FALSE;
    
    NSMutableData* temp_compiled_message; 
    UInt8 datalength = [bac_message_object.data length];
    UInt8 requireddatalength = 0;
    
    switch (bac_message_object.command) {
        case MOBILE__COMMAND_TRANSMIT_POWERSTATE:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_POWERSTATE_DATALENGTH;   
            break;
        case MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ_DATALENGTH;
            break;
        case MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET_DATALENGTH;           
            break;
        case MOBILE__COMMAND_TRANSMIT_REQUEST_USE_COUNT:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_REQUEST_USE_COUNT_DATALENGTH;
            break;
        case MOBILE__COMMAND_TRANSMIT_CALIBRATION_START:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_CALIBRATION_START_DATALENGTH;
            break;
        case MOBILE__COMMAND_TRANSMIT_CALIBRATION_READ:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_CALIBRATION_READ_DATALENGTH;
            break;
        case MOBILE__COMMAND_TRANSMIT_FACTORY_RESET:
            requireddatalength = MOBILE__COMMAND_TRANSMIT_FACTORY_RESET_DATALENGTH;
            break;
        default:
            return FALSE;
            break;
    }
    if(datalength != requireddatalength)
        return FALSE;
    if(datalength < 2){
        bac_message_object.haschecksum = FALSE;
    }else{
        if([BacMessage generateChecksum:bac_message_object] !=TRUE)
            return FALSE;
    }
    
    temp_compiled_message = [[NSMutableData alloc] initWithLength:20];

    UInt8 tempbyte = MOBILE__SOF;
    [temp_compiled_message replaceBytesInRange:NSMakeRange(0,1) withBytes:&tempbyte];
    tempbyte = bac_message_object.command;
    [temp_compiled_message replaceBytesInRange:NSMakeRange(1,1) withBytes:&tempbyte];
    [temp_compiled_message replaceBytesInRange:NSMakeRange(2,datalength) withBytes:[bac_message_object.data bytes]];
    
    if(bac_message_object.haschecksum == TRUE){
        tempbyte = bac_message_object.checksum;
        [temp_compiled_message replaceBytesInRange:NSMakeRange(datalength+2,1) withBytes:&tempbyte];
        tempbyte = MOBILE__EOF;
        [temp_compiled_message replaceBytesInRange:NSMakeRange(datalength+3,1) withBytes:&tempbyte];
    }else{
        tempbyte = MOBILE__EOF;
        [temp_compiled_message replaceBytesInRange:NSMakeRange(datalength+2,1) withBytes:&tempbyte];
    }
    
    *compiled_message_data = [[NSData alloc] initWithBytes:[temp_compiled_message bytes] length:20];
    
    return TRUE;
}


+(BOOL)validateChecksum:(BacMessage*)bac_message_object{
    UInt8 temporary;
    UInt8 crccalculated;
    //MOBILE_'s message checksum value is the XOR of all data byte
    [bac_message_object.data getBytes:&crccalculated range:NSMakeRange(0,1)];
    for (int i =1; i<[bac_message_object.data length]; i++) {
        [bac_message_object.data getBytes:&temporary range:NSMakeRange(i,1)];
        crccalculated = crccalculated^temporary;
    }
    
    if(bac_message_object.checksum == crccalculated)
        return TRUE;
    else
        return FALSE;
}

+(BOOL)generateChecksum:(BacMessage*)bac_message_object{
    UInt8 temporary;
    UInt8 crccalculated;
    if([bac_message_object.data length] == 0)
        return FALSE;
    //MOBILE_'s message checksum value is the XOR of all data byte
    [bac_message_object.data getBytes:&crccalculated range:NSMakeRange(0,1)];
    for (int i =1; i<[bac_message_object.data length]; i++) {
        [bac_message_object.data getBytes:&temporary range:NSMakeRange(i,1)];
        crccalculated = crccalculated^temporary;
    }
    
    bac_message_object.checksum = crccalculated;
    return TRUE;
}


@end
