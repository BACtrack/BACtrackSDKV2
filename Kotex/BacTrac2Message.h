//
//  BacTrac2Message.h
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 2/28/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum BT2Command : uint8_t {
    BT2CommandDeviceIDRequest = 0x70,
    BT2CommandDeviceIDResponse = 0x80,
    BT2CommandStatusReportRequest = 0x71,
    BT2CommandStatusReportResponse = 0x81,
    //?
    BT2CommandErrorReportRequest = 0x72,
    BT2CommandErrorReportResponse = 0x82,
    
    BT2CommandSettingReadRequest = 0x73,
    BT2CommandSettingReadResponse = 0x83,
    BT2CommandSettingWriteRequest = 0x74,
    BT2CommandSettingWriteResponse = 0x84,
    //??
    BT2CommandSettingChangeReportResponse = 0x85,
    
    BT2CommandDeviceControlRequest = 0x76,
    BT2CommandDeviceControlResponse = 0x86,
} BT2Command;

typedef enum BT2SettingParamId : uint8_t {
    BT2SettingBlowTime = 0x00,
    BT2SettingUseCount = 0x01,
    BT2SettingBatteryStatus = 0x10,
    BT2SettingButtonStatus  = 0x20,
    BT2SettingButtonStatusChange = 0x21
} BT2SettingParamId;

typedef enum BT2SettingStatus : uint8_t {
    BT2SettingStatusSuccess = 0x00,
    BT2SettingStatusInvalidParamId = 0x01,
    BT2SettingStatusNotPermitted = 0x02,
    BT2SettingStatusBadLength = 0x03,
    BT2SettingStatusValueNotAccepted = 0x04,
} BT2SettingStatus;

typedef enum BT2ActivityState : uint8_t {
    BT2ActivityStateIdle = 0x00,
    BT2ActivityStateCountDown = 0x01,
    BT2ActivityStateReadyForBlow = 0x02,
    BT2ActivityStateBlowInProgress = 0x03,
    BT2ActivityStateAnalyzing= 0x04,
    BT2ActivityStateIdleWithValidBAC = 0x05,
    BT2ActivityStateCalibrating = 0x06,
    BT2ActivityStatePoweringDown = 0x07
} BT2ActivityState;

typedef enum BT2DeviceControlCommand : uint8_t {
    BT2DeviceStartSequence = 0x00,
    BT2DeviceCancelSequence = 0x01,
    BT2DeviceShutDown = 0x02,
} BT2DeviceControlCommand;

typedef enum BT2ErrorCode : uint8_t {
    BT2ErrorCodeNoError = 0x00,
    BT2ErrorCodeBlowError = 0x01,
    BT2ErrorCodeTemperature = 0x02,
    BT2ErrorCodeLowBattery = 0x03,
    BT2ErrorCodeCalFail = 0x04,
    BT2ErrorCodeNotCal = 0x05,
    BT2ErrorCodeComError = 0x06,
    BT2ErrorCodeInflowError = 0x07,
    BT2ErrorCodeSensorError = 0x08,
    BT2ErrorCodeBACUpperLimit = 0x09
} BT2ErrorCode;

typedef enum BT2ParamId : uint8_t {
    BT2ParamBlowTime = 0x00,
    BT2ParamUseCount = 0x01,
    BT2ParamBattery = 0x10,
    BT2ParamButtonStatus = 0x20,
    BT2ParamButtonStatusChangeReport = 0x21,
    BT2ParamLedStatus = 0x30,
    BT2ParamLedSequence0 = 0x31,
    BT2ParamLedSequence1 = 0x32,
    BT2ParamLedSequence2 = 0x33,
    BT2ParamLedSequence3 = 0x34
} BT2ParamId;

typedef struct {
    uint8_t hardware_id;
    uint8_t hardware_version;
    uint8_t software_id;
    uint8_t software_version;
}DeviceIdResponse;

typedef struct {
    BT2ActivityState activity_state;
    uint8_t battery_level;
    uint8_t heat_count;
    uint16_t bac_reading;
} StatusReportResponse;

typedef struct {
    BT2ErrorCode error_code;
    uint8_t error_info;
} ErrorReportResponse;

typedef struct {
    BT2ParamId param_id;
    uint8_t status;
    uint16_t data;
} SettingReportResponse;


@interface BacTrac2Message : NSObject

@property (readonly, nonatomic, assign) BT2Command command;
//@property (readonly, nonatomic, assign) StatusReportResponse statusReportResponse;

//init with existing packet data, for resending or parsing.
- (id) initWithPacket:(NSData *)data;

//init with a command and data block, will do setup for packet generation.
- (id) initWithCommand:(BT2Command)cmd data:(NSData *)data;

//Get a packet ready for sending down the wire.
- (NSData *)packet;

//No parse errors and valid checksum.
- (BOOL)isValid;

- (StatusReportResponse)statusReportResponse;
- (DeviceIdResponse)deviceIdResponse;
- (ErrorReportResponse)errorReportResponse;
- (SettingReportResponse)settingReportResponse;

+(NSData *)sop;
+(NSData *)eop;

@end
