//
//  BACtrackReactBLEManager.m
//  BACtrack
//
//  Created by Zach Saul on 6/12/18.
//  Copyright © 2018 KHN Solutions. All rights reserved.
//

#import "BACtrackReactBLEManager.h"
#import <React/RCTLog.h>
#import <React/RCTConvert.h>
#import "BacTrackAPI.h"
#import "Breathalyzer.h"

@interface BACtrackReactBLEManager () <BacTrackAPIDelegate>
@end


@implementation RCTConvert (RCTBACtrackDeviceType)
RCT_ENUM_CONVERTER(BACtrackDeviceType, (@{
                                          @"BACtrackDeviceType_Mobile" : @(BACtrackDeviceType_Mobile),
                                          @"BACtrackDeviceType_Vio" : @(BACtrackDeviceType_Vio),
                                          @"BACtrackDeviceType_C6" : @(BACtrackDeviceType_C6),
                                          @"BACtrackDeviceType_C8" : @(BACtrackDeviceType_C8),
                                          @"BACtrackDeviceType_Skyn" : @(BACtrackDeviceType_Skyn),
                                          @"BACtrackDeviceType_Unknown" : @(BACtrackDeviceType_Unknown),
                                          }),
                   BACtrackDeviceType_Mobile, integerValue)
@end

@implementation BACtrackReactBLEManager

RCT_EXPORT_MODULE();


- (id) init
{
    if(self = [super init])
    {
        mBacTrackApi = [[BacTrackAPI alloc] init];
    }
    return self;
}

#pragma mark - EventEmitter methods
- (NSArray<NSString *> *)supportedEvents
{
    return @[@"BacTrackFoundBreathalyzer"];
}

-(void)startObserving
{
    mBacTrackApi.delegate = self;
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving
{
    mBacTrackApi.delegate = nil;
}

- (NSDictionary *) constantsToExport
{
    return @{
      @"BACtrackDeviceType_Mobile" : @(BACtrackDeviceType_Mobile),
      @"BACtrackDeviceType_Vio" : @(BACtrackDeviceType_Vio),
      @"BACtrackDeviceType_C6" : @(BACtrackDeviceType_C6),
      @"BACtrackDeviceType_C8" : @(BACtrackDeviceType_C8),
      @"BACtrackDeviceType_Skyn" : @(BACtrackDeviceType_Skyn),
      @"BACtrackDeviceType_Unknown" : @(BACtrackDeviceType_Unknown),
      };
}
#pragma mark - API Exports

RCT_EXPORT_METHOD(connectToNearestBreathalyzerOfType:(BACtrackDeviceType)type)
{
    RCTLogInfo(@"connectToNearestBreathalyzerOfType: %d", (int)type);
    [mBacTrackApi connectToNearestBreathalyzerOfType:type];
}


RCT_EXPORT_METHOD(disconnect)
{
    [mBacTrackApi disconnect];
}

RCT_EXPORT_METHOD(startScan)
{
    RCTLogInfo(@"Start scan");
    [mBacTrackApi startScan];
}

RCT_EXPORT_METHOD(stopScan)
{
    RCTLogInfo(@"Stop scan");
    [mBacTrackApi stopScan];
}

RCT_EXPORT_METHOD(startFetch)
{
    [mBacTrackApi fetchSkynRecords];
}

RCT_EXPORT_METHOD(startFetchNoDiscard)
{
    [mBacTrackApi fetchSkynRecordsNoDiscard];
}

RCT_EXPORT_METHOD(logSkynDataToFile:(NSString*)filename)
{
    //data will come thru callback (BacTrackSkynResults)
    //Do drainRecords / internalDrain
    //

}

-(void)BacTrackSkynResults:(NSArray *)results
{
    float alcoholSensorValue = [results[0] floatValue];
    float temperatureSensorValue = [results[1] floatValue];
    float accelerationMagnitudeSensorValue = [results[2] floatValue];
    
    //[mBacTrackApi BacTrackSkynResults:results];
}

//API Key declined for some reason (firmware update required, etc)
-(void)BacTrackAPIKeyDeclined:(NSString *)errorMessage
{
    
}

// Any error
-(void)BacTrackError:(NSError*)error
{
    RCTLogInfo(@"!!!!!!!!!!!!!!!!!!ERROR!!!!!!!!!!!!! %@", error);
}

// Successfully connected to BACTrack and found services and characteristics
-(void)BacTrackConnected:(BACtrackDeviceType)device
{
    NSLog(@"BacTrackConnectedYo: %li", (long)device);
}

// Succussfully connected to BACTrack before finding services and characteristics
-(void)BacTrackDidConnect
{
    
}

// Disconnected from BACTrack
-(void)BacTrackDisconnected
{
    
}

// Error connecting to BACTrack
-(void)BacTrackConnectionError
{
    
}

// Attempting to connect to BACTrack timed out
-(void)BacTrackConnectTimeout
{
    
}

// Status of powering on bac sensor
-(void)BacTrackPowerOnBreathalyzerSensor:(BOOL)success
{
    
}

// Status of powering off bac sensor
-(void)BacTrackPowerOffBreathalyzerSensor:(BOOL)success
{
    
}

// Initialized countdown from number, error = TRUE if bac sensor rejects request
-(void)BacTrackCountdown:(NSNumber*)seconds executionFailure:(BOOL)error
{
    
}

// Tell the user to start
-(void)BacTrackStart
{
    
}

// Tell the user to blow
-(void)BacTrackBlow
{
    
}

// BacTrack is analyzing the result
-(void)BacTrackAnalyzing
{
    
}

// Result of the blow
-(void)BacTrackResults:(CGFloat)bac
{
    
}

// Found a breathalyzer while scanning
-(void)BacTrackFoundBreathalyzer:(Breathalyzer*)breathalyzer
{
    [self sendEventWithName:@"BacTrackFoundBreathalyzer" body:@{@"uuid": breathalyzer.uuid,
                                                                @"rssi": breathalyzer.rssi,
                                                                @"type": [NSNumber numberWithInt: breathalyzer.type],
                                                                }];
}

// Returns an integer value representing the number of times the device has been used
-(void)BacTrackUseCount:(NSNumber*)number
{
    
}

-(void)BacTrackFirmwareVersion: (NSString*)version
{
    
}

-(void)BacTrackBatteryVoltage:(NSNumber*)number
{
    
}

-(void)BacTrackBatteryLevel:(NSNumber *)number
{
    
}

-(void)BacTrackTransmitPower:(NSNumber*)number
{
    
}

-(void)BacTrackAdvertising:(BOOL)isAdvertising
{
    
}

-(void)BacTrackSerial:(NSString *)serial_hex
{
    
}

-(void)BacTrackProtectionBit:(NSNumber*)number
{
    
}

-(void)BacTrackUpdatedRSSI:(NSNumber*)number
{
    
}

//Callback for reading Blow Time setting, in units of seconds
-(void)BacTrackBlowTimeSetting:(NSNumber*)seconds
{
    
}

//Callback when setting Blow Time is acknowledged or declined
-(void)BacTrackSetBlowTimeAcknowledgement:(BOOL)acknowledged
{
    
}


//Callback for reading Blow Level setting, (UInt8)setting is of the following values:
//DATECH_BLOWSETTING_LEVEL_LOW
//DATECH_BLOWSETTING_LEVEL_HIGH
-(void)BacTrackBlowLevelSetting:(UInt8)setting
{
    
}


// Callback when the Breathalyzer has an error. Possible errors are as follows:
//DATECH_ERROR_TIME_OUT             -user has not blown when prompted
//DATECH_ERROR_BLOW_ERROR           -flow error
//DATECH_ERROR_OUT_OF_TEMPERATURE   -breathalyzer is operating out of required temperature range
//DATECH_ERROR_LOW_BATTERY          -DATECH breathalyzer is detecting low battery
//DATECH_ERROR_CALIBRATION_FAIL     -Failure in Calibration
//DATECH_ERROR_NOT_CALIBRATED       -Device is not calibrated
//DATECH_ERROR_COM_ERROR            -Communication error
//  Possible temperature states are as follows:
//DATECH_ERROR_TEMPERATURE_HIGH
//DATECH_ERROR_TEMPERATURE_LOW
-(void)BacTrackBreathalyzerError :(UInt8) errortype withTemperature: (UInt8) temperaturestate
{
    
}


//Callback when sensor acknowledges or declines request to enter calibration mode
-(void)BacTrackStartCalibrationAcknowledgement:(BOOL)acknowledged
{
    
}


//Callback returning results of the calibration process. This CB is only returned after the function requestCalibrationCoefficients is called
//Possible result status options are as follows:
// DATECH_CALIBRATION_RESULTS_STATUS_COUNT
// DATECH_CALIBRATION_RESULTS_STATUS_START
// DATECH_CALIBRATION_RESULTS_STATUS_BLOW
// DATECH_CALIBRATION_RESULTS_STATUS_ANALYZING
// DATECH_CALIBRATION_RESULTS_STATUS_TIMEOUT
// DATECH_CALIBRATION_RESULTS_STATUS_BLOW_ERROR
//
//Possible result step options are as follows:
// DATECH_CALIBRATION_RESULTS_STEP_FIRST_LOW
// DATECH_CALIBRATION_RESULTS_STEP_SECOND_LOW
-(void)BacTrackCalibrationResults:(UInt8)step withResultStatus:(UInt8)status withHeatCount:(NSNumber*)number
{
    
}



//Callback indicating the status of the calibration process. Possible status options are as follows:
// DATECH_CALIBRATION_STATE_STATUS_COUNT
// DATECH_CALIBRATION_STATE_STATUS_START
// DATECH_CALIBRATION_STATE_STATUS_BLOW
// DATECH_CALIBRATION_STATE_STATUS_ANALYZING
// DATECH_CALIBRATION_STATE_STATUS_SUCCESS
-(void)BacTrackCalibrationStatus:(UInt8)status withHeatCount:(NSNumber*)number
{
    
}


// Callback for method: -(BOOL)checkForNewFirmware:(NSString*)newFirmwareVersion
// Returns TRUE if the firmware is newer than on the device. FALSE otherwise
-(void)BacTrackFirmwareVersion:(NSString*)version isNewer:(BOOL)isNewer
{
    
}

// Callback for method: -(BOOL)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath;
// Indicates when the uploading of firmware fails.
// Called when not connected to breathalyzer.
// This happens when it sends the writeWithoutResponse packets too fast and packets are dropped
// Solution: Have user try again. Or slow down transfer time in BacTrackOAD.m
-(void)BacTrackOADUploadFailed
{
    
}

// Callback for method: -(BOOL)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath;
// Called when firmware upload is complete
-(void)BacTrackOADUploadComplete
{
    
}

// Callback for method: -(BOOL)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath;
// Called every time the time left changes
-(void)BacTrackOADUploadTimeLeft:(NSNumber*)seconds withPercentage:(NSNumber*)percentageComplete
{
    
}

// Callback for method: -(BOOL)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath;
// Called when firmware images are invalid
// Solution: Use correct images
-(void)BacTrackOADInvalidImage
{
    
}


// Fires when the CBCentralManager changes state.
- (void)BacTrackBluetoothStateChanged:(CBCentralManagerState)newState
{
    
}

@end
