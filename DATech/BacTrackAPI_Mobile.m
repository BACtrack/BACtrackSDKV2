//
//  BacTrackAPI_DATech.m
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/9/14.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//

#import "BacTrackAPI_Mobile.h"
#import "Helper.h"
#import "Globals.h"
#import "Breathalyzer.h"
#import "BacMessage.h"
#import "BacTrackOAD.h"

@interface BacTrackAPI_Mobile () <CBPeripheralDelegate> {
    CBPeripheral     * bacTrack;
    CBService        * serviceOne;
    CBService        * serviceTwo;
    CBService        * serviceBattery;
    CBService        * serviceHardwareVersion;
    CBService        * serviceOAD;
    //CBCharacteristic * countdown_write; // Write to this to start countdown (0x01 and then 0x02)
    CBCharacteristic * countdown_notify; // Subscribe to this for countdown timer
    
    CBCharacteristic * characteristic_hardware_version;
    CBCharacteristic * characteristic_firmware_version;
    CBCharacteristic * characteristic_software_version;
    
    CBCharacteristic * characteristic_led_one;
    CBCharacteristic * characteristic_led_two;
    CBCharacteristic * characteristic_pulse_led;
    
    CBCharacteristic * characteristic_protection;
    CBCharacteristic * characteristic_serial;
    CBCharacteristic * characteristic_advertising;
    CBCharacteristic * characteristic_reset_timeout;
    CBCharacteristic * characteristic_calibration_results;
    CBCharacteristic * characteristic_power_management;
    CBCharacteristic * characteristic_battery_voltage;
    CBCharacteristic * characteristic_transmit_power;
    CBCharacteristic * characteristic_use_count;
    
    CBCharacteristic * characteristic_bac_transmit;
    CBCharacteristic * characteristic_bac_receive;
    
    CBCharacteristic * characteristic_oad_one;
    CBCharacteristic * characteristic_oad_two;
    
    CBCharacteristic * characteristic_powerbreathalyzersensor;
    
    NSTimer          * timer;
    
    BOOL               ignoreDisconnect;
    BOOL               flashLeds;
    BOOL               pulseLedOne;
    BOOL               pulseLedTwo;
    BOOL               locked;
    BOOL               connected;
    BOOL               haltBlow;
    
    UInt8 commandAwaitingAck;
    UInt8 powerStateAwaitingAck;
    
    BacTrackOAD      * oadProfile;
    NSString         * firmwareVersionCompare;
    
    NSNumber *         lastUseCount;
    
    NSTimer *          keepAliveTimer;

    NSTimer *          blowErrorTimeout;
    
    float              lastBatteryVoltage;
    NSInteger          batteryThresholdIndex;
    
    CFAbsoluteTime     blowStartTime;
}

@end

@implementation BacTrackAPI_Mobile
@synthesize delegate=_delegate;


#pragma mark -
#pragma mark Public Methods
/****************************************************************************/
/*								Public Methods                              */
/****************************************************************************/

-(id)init
{
    if (self = [super init]) {
        // Initialized
        
        flashLeds = NO;
        pulseLedOne = NO;
        pulseLedTwo = NO;
        locked = YES;
        connected = NO;
        oadProfile = [BacTrackOAD new];
        lastBatteryVoltage = -1;
        batteryThresholdIndex = 0;
        
    }
    return self;
}

-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral
{
    bacTrack = peripheral;

    self.delegate = delegate;
    
    bacTrack.delegate = self;
 
    return [self init];
}


-(void)configurePeripheral
{
    // Discover services
    NSArray * services = [NSArray arrayWithObjects:[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_ONE],
                          [CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_TWO],
                          [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_BATTERY],
                          [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS],
                          [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_OAD],
                          nil];
    bacTrack.delegate = self;
    [bacTrack discoverServices:services];
}



/// Cleans all characteristics and services
-(void)peripheralDisconnected:(CBPeripheral*)peripheral
{
    connected = NO;
    lastUseCount = nil;
    
    serviceBattery = nil;
    serviceHardwareVersion = nil;
    serviceOAD = nil;
    serviceOne = nil;
    serviceTwo = nil;
    
    // ServiceOne
    countdown_notify = nil;
    //countdown_write = nil;
    characteristic_advertising = nil;
    characteristic_power_management = nil;
    characteristic_use_count = nil;
    characteristic_serial = nil;
    characteristic_reset_timeout = nil;
    characteristic_calibration_results = nil;
    characteristic_protection = nil;
    characteristic_transmit_power = nil;
    characteristic_led_one = nil;
    characteristic_led_two = nil;
    characteristic_pulse_led = nil;
    // ServiceTwo
    characteristic_bac_transmit = nil;
    characteristic_bac_receive = nil;
    
    // ServiceHardwareVersion
    characteristic_hardware_version = nil;
    characteristic_firmware_version = nil;
    
    // ServiceBattery
    characteristic_battery_voltage = nil;
    
    // ServiceOAD
    characteristic_oad_one = nil;
    characteristic_oad_two = nil;
    
    // Tell the OAD that the device disconnected
    [oadProfile deviceDisconnected:bacTrack];
    
    bacTrack = nil;
}


-(BOOL)startCountdown
{
    NSLog(@"Started Mobile countdown");
    //Have breathalyzer send uart command to sensor to turn power state ON
    [self setBreathalyzerPowerState:MOBILE__POWERSTATE_RESTART];
    
    
    Byte val = 0x01;
    NSData *data = [NSData dataWithBytes:&val length:1];
    [bacTrack writeValue:data forCharacteristic:characteristic_powerbreathalyzersensor type:CBCharacteristicWriteWithResponse];
    
    // We must set a delay between writes so that the device has enough time to interperet them
    [self performSelector:@selector(delayedWrite) withObject:nil afterDelay:2];
    
    
    return YES;
}



-(void)getLastUseCount
{
    if (lastUseCount) {
        if ([self.delegate respondsToSelector:@selector(BacTrackUseCount:)]) {
            [self.delegate BacTrackUseCount:lastUseCount];
        }
    }
}

-(void)disconnect
{
    // Don't bother checking for errors. Just disconnect to any connected peripherals
    //    first bit of the 8 will signal a disconnect, and a second bit will signal turning advertising on and off
    //    so for a plain disconnect 0x01
    //        and to silence the radio 0x03
    //        or to stay connected but turn off advertising so the room is less noisy 0x02
    

    if (bacTrack) {
#warning "Need a way to propagate disconnect
        //[cmanager cancelPeripheralConnection:bacTrack];
    }

    if (characteristic_advertising) {
        Byte byte = 0x02;
        NSData * data = [NSData dataWithBytes:&byte length:sizeof(byte)];
        [bacTrack writeValue:data forCharacteristic:characteristic_advertising type:CBCharacteristicWriteWithResponse];
    }
    
    bacTrack = nil;
}


-(void)disableBreathalyzerAdvertising
{
    // Disable Bluetooth
    // 0x00 is normal and default operation.
    //    first bit of the 8 will signal a disconnect, and a second bit will signal turning advertising on and off
    //    so for a plain disconnect 0x01
    //        and to silence the radio 0x03
    //        or to stay connected but turn off advertising so the room is less noisy 0x02
    
    Byte byte = 0x03;
    NSData * data = [NSData dataWithBytes:&byte length:sizeof(byte)];
    [bacTrack writeValue:data forCharacteristic:characteristic_advertising type:CBCharacteristicWriteWithResponse];
}

-(BOOL)checkForNewFirmware:(NSString*)newFirmwareVersion
{
    if (serviceOAD) {
        firmwareVersionCompare = [newFirmwareVersion stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        
        NSLog(@"%@: checkForNewFirmware. Checking for new firmware...", self.class.description);
        
        // Get software version
        if (characteristic_software_version)
            [bacTrack readValueForCharacteristic:characteristic_software_version];
        
        return YES;
    }
    else {
        NSLog(@"%@: checkForNewFirmware. OAD is not supported on this device", self.class.description);
        return NO;
    }
}

-(BACtrackReturnType)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath
{
    if (!connected) {
        if ([self.delegate respondsToSelector:@selector(BacTrackOADUploadFailed)]) {
            [self.delegate BacTrackOADUploadFailed];
        }
        return BACtrackReturnNotConnected;
    }
    else if (serviceOAD) {
        NSLog(@"%@: updateFirmware. Updating Firmware...", self.class.description);
        // Update the firmware
        
        BLEDevice *dev = [BLEDevice new];
        dev.p = bacTrack;
#warning "This isn't tested"
//        dev.manager = cmanager;
        oadProfile.delegate = self.delegate;
        [oadProfile updateFirmwareForDevice:dev withImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath];
        
        return BACtrackReturnTrue;
    }
    else {
        NSLog(@"%@: updateFirmware. OAD is not supported ", self.class.description);
        return BACtrackReturnFalse;
    }
}

-(void)cancelUpdateFirmware
{
    [oadProfile cancelFirmware];
}


-(void)setBreathalyzerTransmitPower:(NSNumber*)power
{
    static Byte max = 0x03;
    
    Byte index = power.unsignedIntegerValue;
    // Only 4 values are available right now
    if (index > max) {
        index = max;
    }
    
    NSData *payload = [NSData dataWithBytes:&index length:sizeof(index)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_transmit_power type:CBCharacteristicWriteWithResponse];
}

-(void)getBreathalyzerTransmitPower
{
    [bacTrack readValueForCharacteristic:characteristic_transmit_power];
}

-(void)getBreathalyzerUseCount
{
    [bacTrack readValueForCharacteristic:characteristic_use_count];
}
-(void)getBreathalyzerSerialNumber
{
    [bacTrack readValueForCharacteristic:characteristic_serial];
}
-(void)getBreathalyzerBatteryVoltage
{
    if (characteristic_battery_voltage)
        [bacTrack readValueForCharacteristic:characteristic_battery_voltage];
}

-(void)getBreathalyzerBatteryLevel
{
    [self getBreathalyzerBatteryVoltage];
}

-(void)getFirmwareVersion
{
    if (characteristic_firmware_version)
        [bacTrack readValueForCharacteristic:characteristic_firmware_version];
}

-(void)setBreathalyzerProtectionBit:(BOOL)enabled
{
    locked = enabled;
    
    if (enabled) {
        // Disable protection
        [bacTrack readValueForCharacteristic:characteristic_protection];
    }
    else {
        // Enable protection mode
        // Write 0x00000000
        
        NSUInteger zero = 0;
        NSData *payload = [NSData dataWithBytes:&zero length:sizeof(zero)];
        [bacTrack writeValue:payload forCharacteristic:characteristic_protection type:CBCharacteristicWriteWithResponse];
    }
}

-(void)resetBACTimeout 
{
    Byte byte = 0x01;
    NSData *payload = [NSData dataWithBytes:&byte length:sizeof(byte)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_reset_timeout type:CBCharacteristicWriteWithResponse];
}

-(void)turnOnLedOne:(BOOL)on
{
    Byte value;
    
    if (on) {
        // Write 1
        value = 0x9F;
    }
    else {
        // Turn off
        value = 0x00;
    }
    
    NSData *payload = [NSData dataWithBytes:&value length:sizeof(value)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_led_one type:CBCharacteristicWriteWithResponse];
}

-(void)turnOnLedTwo:(BOOL)on
{
    Byte value;
    
    if (on) {
        // Write 1
        value = 0x9F;
    }
    else {
        // Turn off
        value = 0x00;
    }
    
    NSData *payload = [NSData dataWithBytes:&value length:sizeof(value)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_led_two type:CBCharacteristicWriteWithResponse];
}

-(void)setLedOneIntensity:(Byte)intensity
{
    NSData *payload = [NSData dataWithBytes:&intensity length:sizeof(intensity)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_led_one type:CBCharacteristicWriteWithResponse];
}

-(void)setLedTwoIntensity:(Byte)intensity
{
    NSData *payload = [NSData dataWithBytes:&intensity length:sizeof(intensity)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_led_two type:CBCharacteristicWriteWithResponse];
}

-(void)pulseLedOne:(BOOL)on
{
    pulseLedOne = on;
    
    Byte value;
    
    if (on) {
        
        if (pulseLedTwo) {
            // Write 0x03
            value = 0x03;
        }
        else {
            // Write 0x01
            value = 0x01;
        }
    }
    else {
        
        if (pulseLedTwo) {
            value = 0x02;
        }
        else {
            value = 0x00;
        }
    }
    
    NSData *payload = [NSData dataWithBytes:&value length:sizeof(value)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_pulse_led type:CBCharacteristicWriteWithResponse];
}

-(void)pulseLedTwo:(BOOL)on
{
    pulseLedTwo = on;
    
    Byte value;
    
    if (on) {
        
        if (pulseLedOne) {
            // Write 0x03
            value = 0x03;
        }
        else {
            // Write 0x01
            value = 0x02;
        }
    }
    else {
        
        if (pulseLedOne) {
            value = 0x01;
        }
        else {
            value = 0x00;
        }
    }
    
    NSData *payload = [NSData dataWithBytes:&value length:sizeof(value)];
    [bacTrack writeValue:payload forCharacteristic:characteristic_pulse_led type:CBCharacteristicWriteWithResponse];
}

-(void)getBreathalyzerRSSI
{
    [bacTrack readRSSI];
}

-(BOOL)isProtectionOn
{
    return locked;
}

-(BOOL)setBreathalyzerBlowTimeSetting:(NSNumber*)seconds
{
    //Convert seconds to byte form
    UInt8 secondsbyte = seconds.unsignedIntegerValue;
    
    //If parameter is invalid, return FALSE
    if(secondsbyte != MOBILE__BLOWSETTING_TIME_3SEC && secondsbyte != MOBILE__BLOWSETTING_TIME_4SEC && secondsbyte != MOBILE__BLOWSETTING_TIME_5SEC)
        return FALSE;
    
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET_DATALENGTH];
    databuffer[0] = MOBILE__BLOWSETTING_TIME;
    
    //Value to write into bac settings
    databuffer[1] = secondsbyte;
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
    
    //Set command that next Ack or Nack will be in response to
    commandAwaitingAck = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET;
    
    return TRUE;
}
-(void)getBreathalyzerBlowTimeSetting
{
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ_DATALENGTH];
    databuffer[0] = MOBILE__BLOWSETTING_TIME;
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
    
}

//Blow Level setting value is one of the following global defines
//MOBILE__BLOWSETTING_LEVEL_LOW
//MOBILE__BLOWSETTING_LEVEL_HIGH
-(BOOL)setBreathalyzerBlowLevelSetting:(UInt8)setting
{
    //If parameter is invalid, return FALSE
    if(setting != MOBILE__BLOWSETTING_LEVEL_LOW && setting != MOBILE__BLOWSETTING_LEVEL_HIGH)
        return FALSE;
    
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET_DATALENGTH];
    databuffer[0] = MOBILE__BLOWSETTING_LEVEL;
    
    //Value to write into bac settings
    databuffer[1] = setting;
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
    
    //Set command that next Ack or Nack will be in response to
    commandAwaitingAck = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET;
    
    return TRUE;
    
}
-(void)getBreathalyzerBlowLevelSetting
{
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ_DATALENGTH];
    databuffer[0] = MOBILE__BLOWSETTING_LEVEL;
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_BLOWSETTING_READ_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
    
}


-(void)startCalibration
{
    //Set command that next Ack or Nack will be in response to
    commandAwaitingAck = MOBILE__COMMAND_TRANSMIT_CALIBRATION_START;
    
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_CALIBRATION_START;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_CALIBRATION_START_DATALENGTH];
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_CALIBRATION_START_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
}

-(void)requestCalibrationCoefficients
{
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_CALIBRATION_READ;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_CALIBRATION_READ_DATALENGTH];
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_CALIBRATION_READ_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
}

-(void)performFactoryReset
{
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_FACTORY_RESET;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_FACTORY_RESET_DATALENGTH];
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_FACTORY_RESET_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];

}

#pragma mark -
#pragma mark Private Methods
/****************************************************************************/
/*								Private Methods                             */
/****************************************************************************/


// Method called after a given delay. Needed because BACTrack devices need 2 writes with the second write
// being a specific delay after the first write.
-(void)delayedWrite
{
    Byte val = 0x02;
    NSData *data = [NSData dataWithBytes:&val length:1];
    [bacTrack writeValue:data forCharacteristic:characteristic_powerbreathalyzersensor type:CBCharacteristicWriteWithResponse];
}

-(void)connectTimeout
{
    NSLog(@"%@: Connection attempt timed out", self.class.description);
    
    // Stop trying to connect if connecting to a peripheral
    [self disconnect];
    
    if ([self.delegate respondsToSelector:@selector(BacTrackConnectTimeout)])
        [self.delegate BacTrackConnectTimeout];
}

-(void)startBacTrackBlow
{
    blowStartTime = CFAbsoluteTimeGetCurrent();
    haltBlow = NO;
    [self.delegate BacTrackBlow:[NSNumber numberWithFloat:1.0]];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self
                                   selector:@selector(bacTrackBlowTimerFired)
                                   userInfo:nil
                                    repeats:NO];
}

-(void)bacTrackBlowTimerFired
{
    if (haltBlow)
    {
        haltBlow = NO;
        return;
    }
    
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    float percentageRemaining = fmax(0, 1.0 - ((now-blowStartTime)/3.7));   // 3.7 seconds is from vestigal BacTrackProxy code. Device-specific.
    [self.delegate BacTrackBlow:[NSNumber numberWithFloat:percentageRemaining]];

    if (percentageRemaining > 0)
    {
        [NSTimer scheduledTimerWithTimeInterval:0.1
                                         target:self
                                       selector:@selector(bacTrackBlowTimerFired)
                                       userInfo:nil
                                        repeats:NO];
    }
}

-(BOOL)setBreathalyzerPowerState:(UInt8)state
{
    //If parameter is invalid, return FALSE
    if(state != MOBILE__POWERSTATE_ON && state != MOBILE__POWERSTATE_OFF && state != MOBILE__POWERSTATE_RESTART)
        return FALSE;
    
    //Create an instance of BAC message object
    BacMessage* transmitbacmessage = [[BacMessage alloc] init];
    
    //Set message command
    transmitbacmessage.command = MOBILE__COMMAND_TRANSMIT_POWERSTATE;
    
    //Create temporary data buffer and set first value based on MOBILE_ protocol
    UInt8 databuffer[MOBILE__COMMAND_TRANSMIT_POWERSTATE_DATALENGTH];
    databuffer[0] = state;
    
    //Submit data to message object
    transmitbacmessage.data = [NSData dataWithBytes:databuffer length:MOBILE__COMMAND_TRANSMIT_POWERSTATE_DATALENGTH];
    
    //Compile message object into 20 byte payload
    NSData* messagepayload;
    [BacMessage compileMessage:&messagepayload fromBacMessage:transmitbacmessage];
    
    //Write Characteristic with 20 byte payload
    [bacTrack writeValue:messagepayload forCharacteristic:characteristic_bac_transmit type:CBCharacteristicWriteWithResponse];
    
    //Set command that next Ack or Nack will be in response to
    commandAwaitingAck = MOBILE__COMMAND_TRANSMIT_POWERSTATE;
    
    powerStateAwaitingAck = state;
    return TRUE;
}

-(void)blowErrorTimedout
{
    [blowErrorTimeout invalidate];
    blowErrorTimeout = nil;
    
    haltBlow = YES;
    NSError *error = [NSError errorWithDomain:@"Breathalyzer time out error" code:MOBILE__ERROR_TIME_OUT userInfo:nil];

    if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
        [self.delegate BacTrackBreathalyzerError:MOBILE__ERROR_TIME_OUT withTemperature:0];
    } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
        [self.delegate BacTrackError:error];
    }
}

#pragma mark -
#pragma mark CBPeripheralDelegate
/****************************************************************************/
/*			     CBPeripheralDelegate protocol methods beneeth here         */
/****************************************************************************/

-(void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(NSError *)error
{
    //if (!error) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(BacTrackUpdatedRSSI:)]) {
            [self.delegate BacTrackUpdatedRSSI:peripheral.RSSI];
        }
    //}
}

-(void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(nonnull NSNumber *)RSSI error:(nullable NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(BacTrackUpdatedRSSI:)])
        [self.delegate BacTrackUpdatedRSSI:RSSI];
}


- (void)determineIndexLevelFromVoltage:(NSNumber *)voltage
{
    // Get the voltage level.
    float voltageLevel = [voltage floatValue];
    
    // If we don't have a previous voltage, record this one and wait till next time.
    if(lastBatteryVoltage < 0)
    {
        if(voltageLevel < kLowBatteryVoltage)
            batteryThresholdIndex = 0;
        else if (voltageLevel < kMediumBatteryVoltage)
            batteryThresholdIndex = 1;
        else if (voltageLevel < kHighBatteryVoltage)
            batteryThresholdIndex = 2;
        else if (voltageLevel < kRidiculousBatteryVoltage)
            batteryThresholdIndex = 3;
        else
            batteryThresholdIndex = 4;
    }
    else
    {
        // At this point we require 2 in a row to change battery level.
        //Check the voltage level, and if we've seen two in a row that are in a certain range, change the index.
        
        // 0-10% range.
        if (voltageLevel <= kLowBatteryVoltage && lastBatteryVoltage <= kLowBatteryVoltage)
            batteryThresholdIndex = 0;
        
        // 10-40% range.
        else if (voltageLevel > kLowBatteryVoltage &&
                 lastBatteryVoltage > kLowBatteryVoltage &&
                 voltageLevel <= kMediumBatteryVoltage &&
                 lastBatteryVoltage <= kMediumBatteryVoltage)
            batteryThresholdIndex = 1;
        
        // 40-70% range.
        else if (voltageLevel > kMediumBatteryVoltage &&
                 lastBatteryVoltage > kMediumBatteryVoltage &&
                 voltageLevel <= kHighBatteryVoltage &&
                 lastBatteryVoltage <= kHighBatteryVoltage)
            batteryThresholdIndex = 2;
        
        // 70-100% range.
        else if (voltageLevel > kHighBatteryVoltage &&
                 lastBatteryVoltage > kHighBatteryVoltage &&
                 voltageLevel <= kRidiculousBatteryVoltage &&
                 lastBatteryVoltage <= kRidiculousBatteryVoltage)
            batteryThresholdIndex = 3;
        
        else if (voltageLevel > kRidiculousBatteryVoltage && lastBatteryVoltage > kRidiculousBatteryVoltage)
            batteryThresholdIndex = 4;
    }
    if ([self.delegate respondsToSelector:@selector(BacTrackBatteryLevel:)])
        [self.delegate BacTrackBatteryLevel:[NSNumber numberWithInt:(batteryThresholdIndex)]];

}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSError *breathalyzerError = nil;

    if (!error) {
        if ([characteristic isEqual:characteristic_bac_receive]) {
            BacMessage* receivedbacmessage = [[BacMessage alloc] init];
            
            //This is size 20 because that currently is the max size of the entire message. It will indefinitely be able to contain the message data
            UInt8 databuffer[20];
            
            if([BacMessage parseMessage:characteristic.value intoBacMessage:receivedbacmessage] == TRUE){
                switch (receivedbacmessage.command) {
                    case MOBILE__COMMAND_RECEIVE_ACK:
                        switch (commandAwaitingAck) {
                            case MOBILE__COMMAND_TRANSMIT_POWERSTATE:
                                switch (powerStateAwaitingAck) {
                                    case MOBILE__POWERSTATE_ON:
                                        if ([self.delegate respondsToSelector:@selector(BacTrackPowerOnBreathalyzerSensor)])
                                            [self.delegate BacTrackPowerOnBreathalyzerSensor:TRUE];
                                        break;
                                    case MOBILE__POWERSTATE_OFF:
                                        if ([self.delegate respondsToSelector:@selector(BacTrackPowerOffBreathalyzerSensor)])
                                            [self.delegate BacTrackPowerOffBreathalyzerSensor:TRUE];
                                        break;
                                    case MOBILE__POWERSTATE_RESTART:
                                        //Continue as normal in code, currently a CB is sent only in case of NACK
                                        break;
                                    default:
                                        break;
                                }
                                break;
                            case MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET:
                                if ([self.delegate respondsToSelector:@selector(BacTrackSetBlowTimeAcknowledgement)])
                                    [self.delegate BacTrackSetBlowTimeAcknowledgement:TRUE];
                                break;
                            case MOBILE__COMMAND_TRANSMIT_CALIBRATION_START:
                                if ([self.delegate respondsToSelector:@selector(BacTrackStartCalibrationAcknowledgement)])
                                    [self.delegate BacTrackStartCalibrationAcknowledgement:TRUE];
                                break;
                            default:
                                break;
                        }
                        break;
                    case MOBILE__COMMAND_RECEIVE_NACK:
                        switch (commandAwaitingAck) {
                            case MOBILE__COMMAND_TRANSMIT_POWERSTATE:
                                switch (powerStateAwaitingAck) {
                                    case MOBILE__POWERSTATE_ON:
                                        if ([self.delegate respondsToSelector:@selector(BacTrackPowerOnBreathalyzerSensor)])
                                            [self.delegate BacTrackPowerOnBreathalyzerSensor:FALSE];
                                        break;
                                    case MOBILE__POWERSTATE_OFF:
                                        if ([self.delegate respondsToSelector:@selector(BacTrackPowerOffBreathalyzerSensor)])
                                            [self.delegate BacTrackPowerOffBreathalyzerSensor:FALSE];
                                        break;
                                    case MOBILE__POWERSTATE_RESTART:
                                        if ([self.delegate respondsToSelector:@selector(BacTrackCountdown:executionFailure:)])
                                            [self.delegate BacTrackCountdown:[NSNumber numberWithInt:(0x00)] executionFailure:TRUE];
                                        break;
                                    default:
                                        break;
                                }
                                break;
                            case MOBILE__COMMAND_TRANSMIT_BLOWSETTING_SET:
                                if ([self.delegate respondsToSelector:@selector(BacTrackSetBlowTimeAcknowledgement)])
                                    [self.delegate BacTrackSetBlowTimeAcknowledgement:FALSE];
                                break;
                            case MOBILE__COMMAND_TRANSMIT_CALIBRATION_START:
                                if ([self.delegate respondsToSelector:@selector(BacTrackStartCalibrationAcknowledgement)])
                                    [self.delegate BacTrackStartCalibrationAcknowledgement:FALSE];
                                break;
                            default:
                                break;
                        }
                        break;
                    case MOBILE__COMMAND_RECEIVE_STATUS:
                        [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_STATUS_DATALENGTH];
                        UInt16 bac = databuffer[1]*256 + databuffer[2];
                        UInt16 usecount = databuffer[4]*256 + databuffer[5];
                        //Status types
                        switch (databuffer[0]) {
                            case MOBILE__STATUS_COUNT:
                                if ([self.delegate respondsToSelector:@selector(BacTrackCountdown:executionFailure:)])
                                    //Believe this countdown value is not is units of seconds
                                    [self.delegate BacTrackCountdown:[NSNumber numberWithInt:(databuffer[3])] executionFailure:FALSE];
                                break;
                            case MOBILE__STATUS_START:
                                [blowErrorTimeout invalidate];
                                blowErrorTimeout = nil;
                                blowErrorTimeout = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(blowErrorTimedout) userInfo:nil repeats:NO];
                                
                                if ([self.delegate respondsToSelector:@selector(BacTrackStart)])
                                    [self.delegate BacTrackStart];
                                break;
                            case MOBILE__STATUS_BLOW:
                                // User blew. Stop timeout
                                [blowErrorTimeout invalidate];
                                blowErrorTimeout = nil;
                                if ([self.delegate respondsToSelector:@selector(BacTrackBlow:)])
                                    [self startBacTrackBlow];
                                else if ([self.delegate respondsToSelector:@selector(BacTrackBlow)])
                                    [self.delegate BacTrackBlow];
                                break;
                            case MOBILE__STATUS_ANALYZING:
                                if ([self.delegate respondsToSelector:@selector(BacTrackAnalyzing)])
                                    [self.delegate BacTrackAnalyzing];
                                break;
                            case MOBILE__STATUS_RESULT:
                                if ([self.delegate respondsToSelector:@selector(BacTrackResults:)])
                                    [self.delegate BacTrackResults:(bac/10000.0f)];
                                break;
                            default:
                                break;
                        }
                        lastUseCount = [NSNumber numberWithInt:(usecount)];
                        if ([self.delegate respondsToSelector:@selector(BacTrackUseCount:)])
                            [self.delegate BacTrackUseCount:[NSNumber numberWithInt:(usecount)]];
                        
                        break;
                    case MOBILE__COMMAND_RECEIVE_ERROR:
                        [blowErrorTimeout invalidate];
                        blowErrorTimeout = nil;
                        
                        [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_ERROR_DATALENGTH];
                        
                        haltBlow = YES;
                        breathalyzerError = [NSError errorWithDomain:@"Breathalyzer error" code:databuffer[0] userInfo:nil];

                        if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
                            [self.delegate BacTrackBreathalyzerError:databuffer[0] withTemperature:databuffer[1]];
                        } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
                            [self.delegate BacTrackError:breathalyzerError];
                        }
                        
                        break;
                    case MOBILE__COMMAND_RECEIVE_BLOW_SETTING:
                        [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_BLOW_SETTING_DATALENGTH];
                        switch (databuffer[0]) {
                            case MOBILE__BLOWSETTING_TIME:
                                if ([self.delegate respondsToSelector:@selector(BacTrackBlowTimeSetting:)])
                                    [self.delegate BacTrackBlowTimeSetting:[NSNumber numberWithUnsignedChar:databuffer[1]]];
                                break;
                            case MOBILE__BLOWSETTING_LEVEL:
                                if ([self.delegate respondsToSelector:@selector(BacTrackBlowLevelSetting:)])
                                    [self.delegate BacTrackBlowLevelSetting:databuffer[0]];
                                break;
                                
                            default:
                                break;
                        }
                        break;
                    /*case MOBILE__COMMAND_RECEIVE_USE_COUNT:
                        [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_USE_COUNT_DATALENGTH];
                        UInt16 usecountrequested = databuffer[1]*256 + databuffer[2];
                        lastUseCount = [NSNumber numberWithInt:(usecountrequested)];
                        if ([self.delegate respondsToSelector:@selector(BacTrackUseCount:)])
                            [self.delegate BacTrackUseCount:[NSNumber numberWithInt:(usecountrequested)]];
                        
                        break;*/
                    case MOBILE__COMMAND_RECEIVE_CALIBRATION_STATUS:
                        [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_CALIBRATION_STATUS_DATALENGTH];
                    
                        if ([self.delegate respondsToSelector:@selector(BacTrackCalibrationStatus: withHeatCount:)])
                            [self.delegate BacTrackCalibrationStatus:databuffer[0] withHeatCount:[NSNumber numberWithUnsignedChar:databuffer[1]]];
                        break;
                    case MOBILE__COMMAND_RECEIVE_CALIBRATION_RESULTS:
                        [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_CALIBRATION_RESULTS_DATALENGTH];
                        
                        if ([self.delegate respondsToSelector:@selector(BacTrackCalibrationResults: withResultStatus: withHeatCount:)])
                            [self.delegate BacTrackCalibrationResults:databuffer[0] withResultStatus:databuffer[1] withHeatCount:[NSNumber numberWithUnsignedChar:databuffer[2]]];
                        break;

                    default:
                        break;
                }
            }
            
        }
        else if ([characteristic isEqual:countdown_notify]) {
            UInt8 data[6];
            [characteristic.value getBytes:data length:SIMPLE_GATT_SERVICE_READ_LEN];
            
            UInt16 bac = data[1]*256 + data[2];
            
            switch (data[0]) {
                case 0x01:
                    if ([self.delegate respondsToSelector:@selector(BacTrackCountdown:executionFailure:)])
                        [self.delegate BacTrackCountdown:[NSNumber numberWithInt:(data[3]/10)] executionFailure:FALSE];
                    break;
                case 0x02:
                    if ([self.delegate respondsToSelector:@selector(BacTrackStart)])
                        [self.delegate BacTrackStart];
                    break;
                case 0x03:
                    if ([self.delegate respondsToSelector:@selector(BacTrackBlow:)])
                        [self startBacTrackBlow];
                    else if ([self.delegate respondsToSelector:@selector(BacTrackBlow)])
                        [self.delegate BacTrackBlow];
                    break;
                case 0x04:
                    if ([self.delegate respondsToSelector:@selector(BacTrackAnalyzing)])
                        [self.delegate BacTrackAnalyzing];
                    break;
                case 0x05:
                    if ([self.delegate respondsToSelector:@selector(BacTrackResults:)])
                        [self.delegate BacTrackResults:(bac/10000.0f)];
                    break;
                default:
                    break;
            }
        }
        else if ([characteristic isEqual:characteristic_firmware_version]) {
            NSString * version = [[NSString alloc] initWithData:characteristic.value encoding:NSASCIIStringEncoding];
            
            if ([self.delegate respondsToSelector:@selector(BacTrackFirmwareVersion:)])
                [self.delegate BacTrackFirmwareVersion:version];
        }
        else if ([characteristic isEqual:characteristic_software_version]) {
            NSString * version = [[NSString alloc] initWithData:characteristic.value encoding:NSASCIIStringEncoding];
            version = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            BOOL newFirmware = NO;
            
            // Check if firmware is newer
            if ([version compare:firmwareVersionCompare] == NSOrderedAscending) {
                // Newer firmware
                newFirmware = YES;
            }
            
            if ([self.delegate respondsToSelector:@selector(BacTrackFirmwareVersion:isNewer:)])
                [self.delegate BacTrackFirmwareVersion:firmwareVersionCompare isNewer:newFirmware];
        }
        else if ([characteristic isEqual:characteristic_battery_voltage]) {
            // A 8 bit value that represents battery voltage range 2.8V(0x00) to 4.3V (0xFF)
            Byte value;
            NSData * data = characteristic.value;
            [data getBytes:&value length:sizeof(value)];
            CGFloat voltage = 3.0f + ((4.2f - 3.0f) * (value * 0.01));
            NSNumber * number = [NSNumber numberWithFloat:voltage];
            [self determineIndexLevelFromVoltage:number];
            if ([self.delegate respondsToSelector:@selector(BacTrackBatteryVoltage:)])
                [self.delegate BacTrackBatteryVoltage:number];
        }
        else if ([characteristic isEqual:characteristic_advertising]) {
            // 0x00 is normal and default operation. Any other value will silence the radio
            
            NSData * data = characteristic.value;
            
            Byte value;
            [data getBytes:&value length:sizeof(value)];
            
            BOOL isAdvertising;
            if (value == 0) {
                isAdvertising = YES;
            }
            else {
                isAdvertising = NO;
            }
            
            if ([self.delegate respondsToSelector:@selector(BacTrackAdvertising:)])
                [self.delegate BacTrackAdvertising:isAdvertising];
            
        }
        else if ([characteristic isEqual:characteristic_serial]) {
            NSData *data = characteristic.value;
            NSUInteger dataLength = [data length];
            NSMutableString *string = [NSMutableString stringWithCapacity:dataLength*2];
            const unsigned char *dataBytes = [data bytes];
            for (NSInteger idx = 0; idx < dataLength; ++idx) {
                [string appendFormat:@"%02x", dataBytes[idx]];
            }
            if ([self.delegate respondsToSelector:@selector(BacTrackSerial:)])
            {
                [self.delegate BacTrackSerial:string];
            }
            
        }
        else if ([characteristic isEqual:characteristic_use_count]) {
            // Record of breathalyzer uses.
            // defaults to 0x0000
            // This will update after every time the BAC is used.
            // iOS app should be able to store non default values in non volatile memory and update value after each use.
            
            NSData * data = characteristic.value;
            
            NSNumber * number;
            Byte byteValue;
            unsigned short unsignedShortValue;
            if (data.length == sizeof(byteValue)) {
                
                [data getBytes:&byteValue length:sizeof(byteValue)];
                
                number = [NSNumber numberWithUnsignedChar:byteValue];
            }
            else if (data.length == sizeof(unsignedShortValue)) {
                [data getBytes:&unsignedShortValue length:sizeof(unsignedShortValue)];
                
                number = [NSNumber numberWithUnsignedShort:unsignedShortValue];
            }
            
            lastUseCount = number;
            if ([self.delegate respondsToSelector:@selector(BacTrackUseCount:)])
                [self.delegate BacTrackUseCount:number];
        }
        else if ([characteristic isEqual:characteristic_reset_timeout]) {
            // 0x00 by default
            // Set to 0x01 to signal to breathalyzer that user will begin calibration
            // Set to 0x02 to request calibration coefficients.
            
            
            
        }
        //The function of the following code is being migrated to the new protocol and is now unused
 /*       else if ([characteristic isEqual:characteristic_calibration_results]) {
            // A flag bit in this characteristic will be asserted when calibration coefficients have been received, updated in characteristic, and are ready for reading by iOS app.
            // Characteristic size is pending further information from DATech.
            // Need to know length and number of coefficients
            
//            NSData * data = characteristic.value;
//            
//            unsigned short value;
//            [data getBytes:&value length:sizeof(value)];
            
            NSNumber * number;
            //number = [NSNumber numberWithUnsignedShort:value];
            
            if ([self.delegate respondsToSelector:@selector(BacTrackCalibrationResults:)])
                [self.delegate BacTrackCalibrationResults:number];
            
        }   */ 
        else if ([characteristic isEqual:characteristic_protection]) {
            // Arbitrary low level of protection over sensitive settings.
            // Set this characteristic to the inverse of the 1 left bit shifted LSB of the breathalyzer’s address (BDA)
            // Example: BDA: 00:18:31:85:21:70
            // inverse(0x70) = 0x8F, 0x8F<<1 = 0x1E
            // In this example, setting this characteristic to 0x1E will unlock test characteristics
            
            NSData * data = characteristic.value;
            
            NSUInteger number;
            [data getBytes:&number length:sizeof(number)];
            
            
            
            // Set protection bit
            number = ~number<<1;
            
            // Inverse number
            // number = number ^ 0xFFFFFFFF;
            
            // Bitwise left shift number
            // number = number << 1;
            
            NSData * payload = [NSData dataWithBytes:&number length:sizeof(number)];
            [bacTrack writeValue:payload forCharacteristic:characteristic_protection type:CBCharacteristicWriteWithResponse];
            
            if ([self.delegate respondsToSelector:@selector(BacTrackProtectionBit:)])
                [self.delegate BacTrackProtectionBit:@YES];

            
        }
        else if ([characteristic isEqual:characteristic_transmit_power]) {
            // For now we plan on having four output strengths ranging from 0x00 to 0x04:
            // maximum ~= 4dBm (0x04) minimum ~= -20dBm (0x00)
            
            NSData * data = characteristic.value;
            
            Byte value;
            [data getBytes:&value length:sizeof(value)];
            
            NSNumber * number = [NSNumber numberWithUnsignedChar:value];
            
            NSNumber * transmitPower;
            switch (number.intValue) {
                case 0:
                    transmitPower = [NSNumber numberWithInteger:-23];
                    break;
                case 1:
                    transmitPower = [NSNumber numberWithInteger:-6];
                    break;
                case 2:
                    transmitPower = [NSNumber numberWithInteger:0];
                    break;
                case 3:
                    transmitPower = [NSNumber numberWithInteger:4];
                    break;
                    
                default:
                    transmitPower = [NSNumber numberWithInteger:0];
                    break;
            }
            
            if ([self.delegate respondsToSelector:@selector(BacTrackTransmitPower:)])
                [self.delegate BacTrackTransmitPower:transmitPower];
        }
        else {
            NSLog(@"%@: Unknown notify update", self.class.description);
            [oadProfile didUpdateValueForProfile:characteristic];
        }

    }    
    else {
        NSLog(@"%@: UpdateValueForCharacteristic failed!", self.class.description);
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (!error) {
        
        if (characteristic == characteristic_reset_timeout) {
            //NSLog(@"%@: Did write value for characteristic_reset_timeout characteristic", self.class.description);
            //[bacTrack readValueForCharacteristic:characteristic_calibration_results];
        }
        else if (characteristic == characteristic_powerbreathalyzersensor) {
            //NSLog(@"%@: Did write value for characteristic_powerbreathalyzersensor characteristic", self.class.description);
        }
        else if (characteristic == characteristic_advertising) {
            //NSLog(@"%@: Did write value for characteristic_advertising characteristic", self.class.description);
        }
        else if (characteristic == characteristic_transmit_power) {
            //NSLog(@"%@: Did write value for characteristic_transmit_power characteristic", self.class.description);
        }
        else if (characteristic == characteristic_protection) {
            //NSLog(@"%@: Did write value for characteristic_protection characteristic", self.class.description);
        }
        else if (characteristic == characteristic_led_one) {
            //NSLog(@"%@: Did write value for characteristic_led_one characteristic", self.class.description);
        }
        else if (characteristic == characteristic_led_two) {
            //NSLog(@"%@: Did write value for characteristic_led_two characteristic", self.class.description);
        }
        else if (characteristic == characteristic_pulse_led) {
            //NSLog(@"%@: Did write value for characteristic_pulse_led characteristic", self.class.description);
        }
        else if (characteristic == characteristic_bac_transmit) {
            //NSLog(@"%@: Did write value for characteristic_bac_transmit characteristic", self.class.description);
        }
        else if (characteristic == characteristic_oad_one) {
            //NSLog(@"%@: Did write value for characteristic_oad_one characteristic", self.class.description);
        }
        else if (characteristic == characteristic_oad_two) {
            //NSLog(@"%@: Did write value for characteristic_oad_two characteristic", self.class.description);
        }
        else {
            //NSLog(@"%@: Did write value for unkown characteristic", self.class.description);
        }
    }
    else {
        //NSLog(@"%@: didWriteValueForCharacteristic failed! UUID: %@", self.class.description, characteristic.UUID);
    }
    
    // Pass on OAD write messages
    if (characteristic == characteristic_oad_one) {
        [oadProfile didWriteValueForProfile:characteristic error:error];
    }
    else if (characteristic == characteristic_oad_two) {
        [oadProfile didWriteValueForProfile:characteristic error:error];
    }
}

-(void)continualBACtrackIdleReset
{
    if (connected && bacTrack.state == CBPeripheralStateConnected) {
        if (characteristic_reset_timeout) {
            [self resetBACTimeout];
        }
        
        [keepAliveTimer invalidate];
        keepAliveTimer = nil;
        keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:120 target:self selector:@selector(continualBACtrackIdleReset) userInfo:nil repeats:NO];
    }
}

-(void)checkAllCharacteristics
{
    if ( // ServiceOne
        (
         countdown_notify &&
         //countdown_write &&
         characteristic_advertising &&
         characteristic_power_management &&
         characteristic_use_count &&
         characteristic_serial &&
         characteristic_reset_timeout &&
         characteristic_calibration_results &&
         characteristic_protection &&
         characteristic_transmit_power &&
         characteristic_led_one &&
         characteristic_led_two &&
         characteristic_pulse_led
         ) &&
        // ServiceTwo
        (
         characteristic_bac_transmit &&
         characteristic_bac_receive
         ) &&
        // ServiceHardwareVersion
        (
         characteristic_hardware_version &&
         characteristic_firmware_version
         ) &&
        // ServiceBattery
        (
         characteristic_battery_voltage
         )
        )
    {
        if (!connected) {
            connected = YES;
            
            // Connect normally
            if ([self.delegate respondsToSelector:@selector(BacTrackConnected:)])
                [self.delegate BacTrackConnected:BACtrackDeviceType_Mobile];
            else if ([self.delegate respondsToSelector:@selector(BacTrackConnected)])
                [self.delegate BacTrackConnected];
            
            // Start resetting BACtrack idle timeout
            [self continualBACtrackIdleReset];
        }
    }
}

/*
 *  @method didDiscoverCharacteristicsForService
 *
 *  @param peripheral Pheripheral that got updated
 *  @param service Service that characteristics where found on
 *  @error error Error message if something went wrong
 *
 *  @discussion didDiscoverCharacteristicsForService is called when CoreBluetooth has discovered
 *  characteristics on a service, on a peripheral after the discoverCharacteristics routine has been called on the service
 *
 */

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (!error) {
        NSLog(@"%@: Characteristics of peripheral found", self.class.description);
        
        if ([service isEqual:serviceOne]) {
            for (CBCharacteristic * characteristic in service.characteristics) {
//                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_COUNTDOWN_WRITE]]) {
//                    countdown_write = characteristic;
//                }
                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_COUNTDOWN_NOTIFY]]) {
                    countdown_notify = characteristic;
                    
                    [bacTrack setNotifyValue:YES forCharacteristic:countdown_notify];
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_SHUTDOWN]]) {
                    characteristic_powerbreathalyzersensor = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_ADVERTISING]]) {
                    characteristic_advertising = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_POWER_MANGEMENT]]) {
                    characteristic_power_management = characteristic;
                    
                    [bacTrack setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:CHARACTERISTIC_SERIAL_MOBILE]]) {
                    characteristic_serial = characteristic;
                    [bacTrack setNotifyValue:YES forCharacteristic:characteristic];

                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_BLOW_COUNT]]) {
                    characteristic_use_count = characteristic;
                    
                    [bacTrack setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_RESET_TIMEOUT]]) {
                    characteristic_reset_timeout = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_CALIBRATION_RESULTS]]) {
                    characteristic_calibration_results = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_PROTECTION]]) {
                    characteristic_protection = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_TRANSMIT_POWER]]) {
                    characteristic_transmit_power = characteristic;
                    
                    [bacTrack setNotifyValue:YES forCharacteristic:characteristic];
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_LED_ONE]]) {
                    characteristic_led_one = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_LED_TWO]]) {
                    characteristic_led_two = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_PULSE_LED]]) {
                    characteristic_pulse_led = characteristic;
                }
            }
            
            if ( //YES || // Do not veryify all characherisitcs! This will be removed
                (
                countdown_notify &&
                //countdown_write &&
                characteristic_advertising &&
                characteristic_power_management &&
                characteristic_serial &&
                characteristic_use_count &&
                characteristic_reset_timeout &&
                characteristic_calibration_results &&
                characteristic_protection &&
                characteristic_transmit_power &&
                characteristic_led_one &&
                characteristic_led_two &&
                characteristic_pulse_led
                 )
                ) {
                NSLog(@"%@: Found all ServiceOne characteristics", self.class.description);
                
                if (flashLeds) {
                    static int duration = 100000;
                    [self turnOnLedOne:NO];
                    [self turnOnLedTwo:NO];
                    usleep(duration);
                    [self turnOnLedOne:YES];
                    [self turnOnLedTwo:YES];
                    usleep(duration);
                    [self turnOnLedOne:NO];
                    [self turnOnLedTwo:NO];
                    usleep(duration);
                    [self turnOnLedOne:YES];
                    [self turnOnLedTwo:YES];
                    usleep(duration);
                    [self turnOnLedOne:NO];
                    [self turnOnLedTwo:NO];
                    usleep(duration);
                    [self turnOnLedOne:YES];
                    [self turnOnLedTwo:YES];
                    usleep(duration);
                    [self turnOnLedOne:NO];
                    [self turnOnLedTwo:NO];
                    usleep(duration);
                    [self turnOnLedOne:YES];
                    [self turnOnLedTwo:YES];
                    usleep(duration);
                    [self turnOnLedOne:NO];
                    [self turnOnLedTwo:NO];
                    usleep(duration);
                    [self turnOnLedOne:YES];
                    [self turnOnLedTwo:YES];
                    
                    
                    [self disconnect];
                    return;
                }
                
            }
            else {
                // Could not find all characteristics!
                NSLog(@"%@: Could not find all ServiceOne characteristics!", self.class.description);
                if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
                    [self.delegate BacTrackConnectionError];
            }
        }
        else if ([service isEqual:serviceTwo]) {
            for (CBCharacteristic * characteristic in service.characteristics) {
                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_TRANSMIT]]) {
                    characteristic_bac_transmit = characteristic;
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_RECEIVE]]) {
                    characteristic_bac_receive = characteristic;
                    
                    [bacTrack setNotifyValue:YES forCharacteristic:characteristic];
                }
            }
            
            if ( //YES || // Do not veryify all characherisitcs! This will be removed
                (
                 characteristic_bac_transmit &&
                 characteristic_bac_receive
                 )
                ) {
                NSLog(@"%@: Found all ServiceTwo characteristics", self.class.description);
                
            }
            else {
                // Could not find all characteristics!
                NSLog(@"%@: Could not find all ServiceTwo characteristics!", self.class.description);
                if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
                    [self.delegate BacTrackConnectionError];
            }
        }
        else if ([service isEqual:serviceBattery]) {
            for (CBCharacteristic * characteristic in service.characteristics) {
                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY]]) {
                    characteristic_battery_voltage = characteristic;
                    
                    [bacTrack setNotifyValue:YES forCharacteristic:characteristic];
                    
                }
            }
            
            if ( //YES || // Do not veryify all characherisitcs! This will be removed
                (
                 characteristic_battery_voltage
                 )
                ) {
                NSLog(@"%@: Found battery characteristics", self.class.description);
            }
            else {
                // Could not find all characteristics!
                NSLog(@"%@: Could not find all battery characteristics!", self.class.description);
                if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
                    [self.delegate BacTrackConnectionError];
            }
        }
        else if ([service isEqual:serviceHardwareVersion]) {
            for (CBCharacteristic * characteristic in service.characteristics) {
                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_HARDWARE_VERSION]]) {
                    characteristic_hardware_version = characteristic;
                    
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION]]) {
                    characteristic_firmware_version = characteristic;
                    
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_SOFTWARE_VERSION]]) {
                    characteristic_software_version = characteristic;
                }
                
            }
            
            if ( //YES || // Do not veryify all characherisitcs! This will be removed
                (
                 characteristic_hardware_version &&
                 characteristic_firmware_version
                 )
                ) {
                NSLog(@"%@: Found version characteristics", self.class.description);
            }
            else {
                // Could not find all characteristics!
                NSLog(@"%@: Could not find all hardware version characteristics!", self.class.description);
                if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
                    [self.delegate BacTrackConnectionError];
            }
        }
        else if ([service isEqual:serviceOAD]) {
            for (CBCharacteristic * characteristic in service.characteristics) {
                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_ONE]]) {
                    characteristic_oad_one = characteristic;
                    
                }
                else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_TWO]]) {
                    characteristic_oad_two = characteristic;
                }
                
            }
        }
        
        [self checkAllCharacteristics];
        
        
        
        
        
    }
    else {
        NSLog(@"%@: Characteristics discovery was unsuccessful", self.class.description);
        
        if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
            [self.delegate BacTrackConnectionError];
        
        // Disconnect from peripheral
        [self disconnect];
    }
}


/*
 *  @method didDiscoverServices
 *
 *  @param peripheral Pheripheral that got updated
 *  @error error Error message if something went wrong
 *
 *  @discussion didDiscoverServices is called when CoreBluetooth has discovered services on a
 *  peripheral after the discoverServices routine has been called on the peripheral
 *
 */

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (!error) {
        NSLog(@"%@: Services of peripheral found", self.class.description);
        
        // Discover characteristics of found services
        for (CBService * service in bacTrack.services) {
            // Save service one
            if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_ONE]]) {
                serviceOne = service;
            
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_COUNTDOWN_NOTIFY],
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_SHUTDOWN],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_ADVERTISING],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_POWER_MANGEMENT],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_BLOW_COUNT],
                                             [CBUUID UUIDWithString:CHARACTERISTIC_SERIAL_MOBILE],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_RESET_TIMEOUT],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_CALIBRATION_RESULTS],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_PROTECTION],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_TRANSMIT_POWER],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_LED_ONE],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_LED_TWO],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_PULSE_LED],
                                             nil];
            
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            else if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_TWO]]) {
                serviceTwo = service;
                
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_TRANSMIT],
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_RECEIVE],
                                             nil];
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            else if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_BATTERY]]) {
                serviceBattery = service;
                
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY],
                                             nil];
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            else if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS]]) {
                serviceHardwareVersion = service;
                
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_HARDWARE_VERSION],
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION],
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_SOFTWARE_VERSION],
                                             nil];
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            
            else if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_OAD]]) {
                serviceOAD = service;
                
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_ONE],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_TWO],
                                             nil];
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
        }
    }
    else {
        NSLog(@"%@: Service discovery was unsuccessful", self.class.description);
        
        if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
            [self.delegate BacTrackConnectionError];
        
        // Disconnect from peripheral
        [self disconnect];
    }
}


@end
