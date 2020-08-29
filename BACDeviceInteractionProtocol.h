//
//  BACDeviceInteractionProtocol.h
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/9/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BacTrackAPIDelegate.h"

@protocol BACDeviceInteractionProtocol <NSObject>

#define kRidiculousBatteryVoltage 5.9
#define kHighBatteryVoltage 4.0
#define kMediumBatteryVoltage 3.8
#define kLowBatteryVoltage 3.7

// Callback delegate. Must be set
@property (strong, nonatomic) id<BacTrackAPIDelegate> delegate;

-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral;

/* Public method calls: */

-(void)getFirmwareVersion;

// Start BACTrack countdown
-(BOOL)startCountdown;


// Disables the breathalyzers bluetooth
-(void)disableBreathalyzerAdvertising;

-(void)setBreathalyzerProtectionBit:(BOOL)enabled;

-(void)resetBACTimeout;

-(void)setBreathalyzerTransmitPower:(NSNumber*)power;
-(void)getBreathalyzerTransmitPower;
-(void)getBreathalyzerBatteryVoltage;
-(void)getBreathalyzerBatteryLevel;
-(void)getBreathalyzerUseCount;
-(void)getBreathalyzerSerialNumber;

-(void)turnOnLedOne:(BOOL)on;
-(void)turnOnLedTwo:(BOOL)on;

-(void)pulseLedOne:(BOOL)on;
-(void)pulseLedTwo:(BOOL)on;

// Byte value is between 0-255 which determines the LED intensity. When the method is called the LED with adjust immediately to the provided value.
-(void)setLedOneIntensity:(Byte)intensity;
-(void)setLedTwoIntensity:(Byte)intensity;


-(BOOL)setBreathalyzerBlowTimeSetting:(NSNumber*)seconds;
-(void)getBreathalyzerBlowTimeSetting;

//Blow Level setting value is one of the following global defines
//DATECH_BLOWSETTING_LEVEL_LOW
//DATECH_BLOWSETTING_LEVEL_HIGH
-(BOOL)setBreathalyzerBlowLevelSetting:(UInt8)setting;
-(void)getBreathalyzerBlowLevelSetting;

-(void)getBreathalyzerRSSI;

// Connected to breathalyzer. Else timesout after given duration in seconds
-(void)flashBreathalyzerLEDs:(Breathalyzer*)breathalyzer withTimeout:(NSTimeInterval)timeout;

-(BOOL)isProtectionOn;

// Starts breathalyzer calibration
-(void)startCalibration;

// Request calibration coefficients
-(void)requestCalibrationCoefficients;

// Resets the Breathalyzer device
-(void)performFactoryReset;

// Requests the last cached use count from the breathalyzer
// Callback method:
// -(void)BacTrackUseCount:(NSNumber*)number;
-(void)getLastUseCount;


// Returns FALSE if OAD is not supported on the device. TRUE otherwise
// See callback method: -(void)BacTrackFirmwareVersion:(NSString*)version isNewer:(BOOL)isNewer;
-(BOOL)checkForNewFirmware:(NSString*)newFirmwareVersion;

// Returns BACtrackReturnFalse if OAD is not supported on the device. Returns BACtrackReturnTrue if OAD is supported. Returns BACtrackReturnNotConnected when the breathalyzer is not connected.
// Parameters imageApath and imageBpath are full paths to the images .bin files
// See callback methods:
//-(void)BacTrackOADUploadFailed;
//-(void)BacTrackOADUploadComplete;
//-(void)BacTrackOADUploadTimeLeft:(NSNumber*)seconds withPercentage:(NSNumber*)percentageComplete;
//-(void)BacTrackOADInvalidImage;
-(BACtrackReturnType)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath;

// Cancels firmware update
// No callbacks needed
-(void)cancelUpdateFirmware;

@optional
- (CBManagerState)getState;

@end
