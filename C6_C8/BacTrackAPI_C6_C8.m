//
//  BacTrackAPI_C6.m
//  BacTrackManagement
//
//  Created by Daniel Walton on 8/10/17
//  Copyright (c) 2017 KHN Solutions LLC. All rights reserved.
//

#import "BacTrackAPI_C6_C8.h"
#import "Helper.h"
#import "Globals.h"
#import "Breathalyzer.h"
#import "BacMessage.h"
#import "BacTrackOAD.h"

@interface BacTrackAPI_C6 () <CBPeripheralDelegate> {
    CBPeripheral     * bacTrack;
    CBService        * serviceSerial;
    CBService        * serviceVersions;
    CBService        * serviceOAD;
    CBCharacteristic * charIdentify;
    CBCharacteristic * charBlock;
    CBCharacteristic * charCount;
    CBCharacteristic * charStatus;
    CBCharacteristic * charFirmware;
    CBCharacteristic * characteristicSerial; // Subscribe to this for countdown timer
    
    
    NSTimer          * timer;
    
    BOOL               ignoreDisconnect;
    BOOL               locked;
    BOOL               connected;
    BOOL               haltBlow;
    
    UInt8 commandAwaitingAck;
    UInt8 powerStateAwaitingAck;
    
    NSData           * firmwareData;

    NSString         * firmwareVersionCompare;
    
    NSNumber *         lastUseCount;
    
    float              lastBatteryVoltage;
    NSInteger          batteryThresholdIndex;
    
    CFAbsoluteTime     blowStartTime;
}

@end

@implementation BacTrackAPI_C6
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
        connected = NO;
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
    NSArray * services = [NSArray arrayWithObjects:[CBUUID UUIDWithString:C6_SERIAL_GATT_SERVICE_UUID],
                                                   [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_OAD],
                                                   [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS],
                                                    nil];
    bacTrack.delegate = self;
    [bacTrack discoverServices:services];
}


/// Cleans all characteristics and services
-(void)peripheralDisconnected:(CBPeripheral*)peripheral
{
    connected = NO;
    lastUseCount = nil;
    characteristicSerial = nil;
    
    bacTrack = nil;
}


-(BOOL)startCountdown
{
    NSLog(@"Started Mobile countdown");

    Byte val[2];
    val[0] = 0x00;
    val[1] = 0x01;
    NSData *data = [NSData dataWithBytes:&val length:2];
    [bacTrack writeValue:data forCharacteristic:characteristicSerial type:CBCharacteristicWriteWithResponse];
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
    bacTrack = nil;
}


-(BOOL)checkForNewFirmware:(NSString*)newFirmwareVersion
{
    firmwareVersionCompare = [newFirmwareVersion copy];
    [bacTrack readValueForCharacteristic:charFirmware];
    return true;
}

-(BACtrackReturnType)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath
{
    if (!connected) {
        if ([self.delegate respondsToSelector:@selector(BacTrackOADUploadFailed)]) {
            [self.delegate BacTrackOADUploadFailed];
        }
        return BACtrackReturnNotConnected;
    }
    else {
        firmwareData = [NSData dataWithContentsOfFile:imageApath];
        [firmwareData copy];
        NSData *metadata = [NSData dataWithBytes:firmwareData.bytes length:16];
        [bacTrack writeValue:metadata forCharacteristic:charIdentify type:CBCharacteristicWriteWithResponse];
        return BACtrackReturnTrue;
    }
}

-(void)cancelUpdateFirmware
{
}



-(void)getBreathalyzerUseCount
{
    Byte val[2];
    val[0] = 0x05;
    val[1] = USECOUNT_SETTING_ID;
    NSData *data = [NSData dataWithBytes:&val length:2];
    [bacTrack writeValue:data forCharacteristic:characteristicSerial type:CBCharacteristicWriteWithResponse];

}
-(void)getBreathalyzerSerialNumber
{
    //[bacTrack readValueForCharacteristic:characteristic_serial];
}
-(void)getBreathalyzerBatteryVoltage
{
    Byte val[1];
    val[0] = 0x08;
    NSData *data = [NSData dataWithBytes:&val length:1];
    [bacTrack writeValue:data forCharacteristic:characteristicSerial type:CBCharacteristicWriteWithResponse];
    //if (characteristic_battery_voltage)
    //    [bacTrack readValueForCharacteristic:characteristic_battery_voltage];
}

-(void)getBreathalyzerBatteryLevel
{
    [self getBreathalyzerBatteryVoltage];
}

-(void)getFirmwareVersion
{
    //if (characteristic_firmware_version)
    //    [bacTrack readValueForCharacteristic:characteristic_firmware_version];
}


-(void)getBreathalyzerRSSI
{
    [bacTrack readRSSI];
}

- (void)disableBreathalyzerAdvertising {
    return;
}


- (void)flashBreathalyzerLEDs:(Breathalyzer *)breathalyzer withTimeout:(NSTimeInterval)timeout {
    return;
}


- (void)getBreathalyzerBlowLevelSetting {
    return;
}


- (void)getBreathalyzerBlowTimeSetting {
    return;
}


- (void)getBreathalyzerTransmitPower {
    return;
}


- (CBCentralManagerState)getState {
    return CBCentralManagerStateUnknown;
}


- (BOOL)isProtectionOn {
    return NO;
}


- (void)performFactoryReset {
    return;
}


- (void)pulseLedOne:(BOOL)on {
    return;
}


- (void)pulseLedTwo:(BOOL)on {
    return;
}


- (void)requestCalibrationCoefficients {
    return;
}


- (void)resetBACTimeout {
    return;
}


- (BOOL)setBreathalyzerBlowLevelSetting:(UInt8)setting {
    return YES;
}


- (BOOL)setBreathalyzerBlowTimeSetting:(NSNumber *)seconds {
    return YES;
}


- (void)setBreathalyzerProtectionBit:(BOOL)enabled {
    return;
}


- (void)setBreathalyzerTransmitPower:(NSNumber *)power {
    return;
}

//- (void)flashBreathalyzerLEDs:(Breathalyzer *)breathalyzer withTimeout:(NSTimeInterval)timeout {
    //@throw([NSException exceptionWithName:@"Unimplemented" reason:@"flashBreathalyzerLEDs:(Breathalyzer *)breathalyzer withTimeout:(NSTimeInterval)timeout for BACtrack C6" userInfo:nil]);
//}



- (void)setLedOneIntensity:(Byte)intensity {
    return;
}


- (void)setLedTwoIntensity:(Byte)intensity {
    return;
}


- (void)startCalibration {
    return;
}


- (void)turnOnLedOne:(BOOL)on {
    return;
}


- (void)turnOnLedTwo:(BOOL)on {
    return;
}




#pragma mark -
#pragma mark Private Methods
/****************************************************************************/
/*								Private Methods                             */
/****************************************************************************/

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
        blowStartTime = 0;
        haltBlow = NO;
        return;
    }
    
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    float percentageRemaining = fmax(0, 1.0 - ((now-blowStartTime)/4.0));   // 4.0 seconds is from inspection of C6 and C8 units
    [self.delegate BacTrackBlow:[NSNumber numberWithFloat:percentageRemaining]];

    if (percentageRemaining > 0)
    {
        [NSTimer scheduledTimerWithTimeInterval:0.1
                                         target:self
                                       selector:@selector(bacTrackBlowTimerFired)
                                       userInfo:nil
                                        repeats:NO];
    }
    else
    {
        blowStartTime = 0;
    }
}

// Method called after a given delay. Needed because BACTrack devices need 2 writes with the second write
// being a specific delay after the first write.
-(void)delayedWrite
{
    Byte val = 0x02;
    NSData *data = [NSData dataWithBytes:&val length:1];
    //[bacTrack writeValue:data forCharacteristic:characteristic_powerbreathalyzersensor type:CBCharacteristicWriteWithResponse];
}

-(void)connectTimeout
{
    NSLog(@"%@: Connection attempt timed out", self.class.description);
    
    // Stop trying to connect if connecting to a peripheral
    [self disconnect];
    
    if ([self.delegate respondsToSelector:@selector(BacTrackConnectTimeout)])
        [self.delegate BacTrackConnectTimeout];
}



-(BOOL)setBreathalyzerPowerState:(UInt8)state
{
    return TRUE;
}

-(void)blowErrorTimedout
{
    NSError *error = [NSError errorWithDomain:@"Breathalyzer time out error" code:MOBILE__ERROR_TIME_OUT userInfo:nil];
    haltBlow = YES;
    
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
    // Values from inspecting AAA battery data sheet found here: https://data.energizer.com/PDFs/E92.pdf
    // And here for rechargeables: https://data.energizer.com/pdfs/nickelmetalhydride_appman.pdf
    // These values are a compromise between the two
    static float kLowBatteryVoltageAAA = 1.05;
    static float kMediumBatteryVoltageAAA = 1.15;
    // This might seem low, but rechargables put this out when almost fully charged
    // (drops from 1.4 quickly to 1.2, then hangs around 1.2 for most of its life)
    static float kHighBatteryVoltageAAA = 1.3;
    static float kRidiculousBatteryVoltageAAA = 1.8;
    
    // Get the voltage level.
    float voltageLevel = [voltage floatValue];
    
    // If we don't have a previous voltage, record this one and wait till next time.
    if(lastBatteryVoltage < 0)
    {
        if(voltageLevel < kLowBatteryVoltageAAA)
            batteryThresholdIndex = 0;
        else if (voltageLevel < kMediumBatteryVoltageAAA)
            batteryThresholdIndex = 1;
        else if (voltageLevel < kHighBatteryVoltageAAA)
            batteryThresholdIndex = 2;
        else if (voltageLevel < kRidiculousBatteryVoltageAAA)
            batteryThresholdIndex = 3;
        else
            batteryThresholdIndex = 4;
    }
    else
    {
        // At this point we require 2 in a row to change battery level.
        //Check the voltage level, and if we've seen two in a row that are in a certain range, change the index.
        
        // 0-10% range.
        if (voltageLevel <= kLowBatteryVoltageAAA && lastBatteryVoltage <= kLowBatteryVoltageAAA)
            batteryThresholdIndex = 0;
        
        // 10-40% range.
        else if (voltageLevel > kLowBatteryVoltageAAA &&
                 lastBatteryVoltage > kLowBatteryVoltageAAA &&
                 voltageLevel <= kMediumBatteryVoltageAAA &&
                 lastBatteryVoltage <= kMediumBatteryVoltageAAA)
            batteryThresholdIndex = 1;
        
        // 40-70% range.
        else if (voltageLevel > kMediumBatteryVoltageAAA &&
                 lastBatteryVoltage > kMediumBatteryVoltageAAA &&
                 voltageLevel <= kHighBatteryVoltageAAA &&
                 lastBatteryVoltage <= kHighBatteryVoltageAAA)
            batteryThresholdIndex = 2;
        
        // 70-100% range.
        else if (voltageLevel > kHighBatteryVoltageAAA &&
                 lastBatteryVoltage > kHighBatteryVoltageAAA &&
                 voltageLevel <= kRidiculousBatteryVoltageAAA &&
                 lastBatteryVoltage <= kRidiculousBatteryVoltageAAA)
            batteryThresholdIndex = 3;
        
        else if (voltageLevel > kRidiculousBatteryVoltageAAA && lastBatteryVoltage > kRidiculousBatteryVoltageAAA)
            batteryThresholdIndex = 4;
    }
    if ([self.delegate respondsToSelector:@selector(BacTrackBatteryLevel:)])
        [self.delegate BacTrackBatteryLevel:[NSNumber numberWithInt:((int)batteryThresholdIndex)]];

}
#define OAD_BLOCK_SIZE 16
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (characteristic==charIdentify)
    {
        fprintf(stderr,"identify\n");
    }
    else if (characteristic==charFirmware)    {
        NSString * org_version = [[NSString alloc] initWithData:characteristic.value encoding:NSASCIIStringEncoding];
        NSCharacterSet *inverted = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        NSArray *components = [org_version componentsSeparatedByCharactersInSet:inverted];
        NSString *version = [components componentsJoinedByString:@""];
        components = [firmwareVersionCompare componentsSeparatedByCharactersInSet:inverted];
        NSString * versionComp = [components componentsJoinedByString:@""];
        
        BOOL newFirmware = NO;
        int iversion = [version intValue];
        int icomp = [versionComp intValue];
        if (icomp > iversion) {
            newFirmware = YES;
        }
        // Check if firmware is newer
        
        if ([self.delegate respondsToSelector:@selector(BacTrackFirmwareVersion:isNewer:)])
            [self.delegate BacTrackFirmwareVersion:org_version isNewer:newFirmware];
    }
    else if (characteristic==charStatus)
    {
        char status = 0;
        [characteristic.value getBytes:&status length:1];
        if (status == 0 ) //success
        {
            [self.delegate BacTrackOADUploadComplete];
        }
        else
        {
            [self.delegate BacTrackOADUploadFailed];
        }
        
        fprintf(stderr,"status %x\n",status);
    }
    else if (characteristic==charBlock)
    {
        unsigned short blocknum = 0;
        [characteristic.value getBytes:&blocknum length:2];
        float percentage = blocknum*OAD_BLOCK_SIZE/(float)firmwareData.length;
        float seconds = 3*60*(1-percentage);
        [self.delegate BacTrackOADUploadTimeLeft:[NSNumber numberWithFloat:seconds] withPercentage:[NSNumber numberWithFloat:percentage]];
        //for (int i=0;i<4;i++)
        {
            if (blocknum*OAD_BLOCK_SIZE>=firmwareData.length) {
                
            } else {
                NSMutableData *packet = [NSMutableData dataWithBytes:&blocknum length:2];
                [packet appendBytes:firmwareData.bytes+(blocknum*OAD_BLOCK_SIZE) length:OAD_BLOCK_SIZE];
                [bacTrack writeValue:packet forCharacteristic:charBlock type:CBCharacteristicWriteWithResponse];
            }
            blocknum ++;
        }
    }
    else if (characteristic==charCount)
    {
        fprintf(stderr,"count\n");
    }
    if (characteristic==characteristicSerial)
    {
        Byte CLEARING_EVT = 0x01;
        Byte WAITING_FOR_BLOW_EVT = 0x02;
        Byte BLOW_IN_PROGRESS_EVT = 0x03;
        Byte COMPLETED_EVT = 0x06;
        Byte TEST_CANCELLED_EVT = 0x0D;
        Byte BLOW_TIMEOUT_ERROR_EVT = 0x07;
        Byte INSUFFICIENT_BLOW_ERROR_EVT = 0x08;
        Byte GENERAL_ERROR_EVT = 0x09;
        Byte LOW_BATTERY_ERROR_EVT = 0x0A;
        Byte LOW_TEMP_ERROR_EVT = 0x0B;
        Byte HIGH_TEMP_ERROR_EVT = 0x0C;
        Byte UNCALIBRATED_EVT = 0x0E;
        Byte MAX_BAC_EXCEEDED_EVT = 0x0F;

        Byte *msg = (Byte *)characteristic.value.bytes;
        if (msg[0]==0x80)
        {
            Byte status = msg[1];
            Byte count = msg[2];
            
            if (status == CLEARING_EVT)
            {
                if ([self.delegate respondsToSelector:@selector(BacTrackCountdown:executionFailure:)])
                    [self.delegate BacTrackCountdown:[NSNumber numberWithChar:count] executionFailure:NO];
            }
            else if (status == WAITING_FOR_BLOW_EVT)
            {
                [self.delegate BacTrackStart];
            }
            else if (status == BLOW_IN_PROGRESS_EVT)
            {
                if (count==0)
                {
                    haltBlow = YES;
                    [(NSObject *)self.delegate performSelector:@selector(BacTrackAnalyzing) withObject:nil afterDelay:1.0];
                }
                else
                {
                    // The C6 and C8 will send multiple BLOW_IN_PROGRESS_EVTs during the
                    // course of a blow. Only start the timer once.
                    if ([self.delegate respondsToSelector:@selector(BacTrackBlow:)])
                    {
                        if (blowStartTime == 0)
                            [self startBacTrackBlow];
                    }
                    else
                    {
                        [self.delegate BacTrackBlow];
                    }
                }
            }
            else if (status == COMPLETED_EVT)
            {
                unsigned short bac = 0;
                Byte *bp = (Byte *)&bac;
                Byte b1 = msg[3];
                Byte b2 = msg[4];
                bp[0] = b2;
                bp[1] = b1;
                
                [self.delegate BacTrackResults:bac/1000.0];
            }
            else if (status == TEST_CANCELLED_EVT)
            {
            }
            else if (status == BLOW_TIMEOUT_ERROR_EVT)
            {
                NSError *error = [NSError errorWithDomain:@"Breathalyzer time out error" code:MOBILE__ERROR_TIME_OUT userInfo:nil];
                
                haltBlow = YES;
                if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
                    [self.delegate BacTrackBreathalyzerError:MOBILE__ERROR_TIME_OUT withTemperature:0];
                } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
                    [self.delegate BacTrackError:error];
                }
 
            }
            else if (status == INSUFFICIENT_BLOW_ERROR_EVT)
            {
                NSError *error = [NSError errorWithDomain:@"Breathalyzer blow error" code:MOBILE__ERROR_BLOW_ERROR userInfo:nil];
                
                haltBlow = YES;
                if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
                    [self.delegate BacTrackBreathalyzerError:MOBILE__ERROR_TIME_OUT withTemperature:0];
                } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
                    [self.delegate BacTrackError:error];
                }
            }
            else if (status == GENERAL_ERROR_EVT)
            {
                haltBlow = YES;
                [self.delegate BacTrackError:nil];
            }
            else if (status == LOW_BATTERY_ERROR_EVT)
            {
                NSError *error = [NSError errorWithDomain:@"Breathalyzer low battery error" code:MOBILE__ERROR_LOW_BATTERY userInfo:nil];
                haltBlow = YES;
                if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
                    [self.delegate BacTrackBreathalyzerError:MOBILE__ERROR_LOW_BATTERY withTemperature:0];
                } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
                    [self.delegate BacTrackError:error];
                }
            }
            else if (status == LOW_TEMP_ERROR_EVT)
            {
                haltBlow = YES;
                [self.delegate BacTrackError:nil];
            }
            else if (status == HIGH_TEMP_ERROR_EVT)
            {
                haltBlow = YES;
                [self.delegate BacTrackError:nil];
            }
            else if (status == UNCALIBRATED_EVT) {
                haltBlow = YES;
                [self.delegate BacTrackError:nil];
            }
            else if (status == MAX_BAC_EXCEEDED_EVT)
            {
                haltBlow = YES;
                NSError *error = [NSError errorWithDomain:@"Breathalyzer BAC exceeded maximum" code:ERROR_BAC_UPPER_LIMIT userInfo:nil];
                if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
                    [self.delegate BacTrackBreathalyzerError:MOBILE__ERROR_LOW_BATTERY withTemperature:0];
                } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
                    [self.delegate BacTrackError:error];
                }
            }
            else {
                NSLog(@"BACTrack C6/C8 event unknown: %02x\n",status);
            }
        } else if (msg[0]==0x88) {
            unsigned short millivolts = 0;
            memcpy(&millivolts,msg+1,2);
            float volts = millivolts / 1000.0;
            NSNumber *num = [NSNumber numberWithFloat:volts];
            [self determineIndexLevelFromVoltage:num];
            [self.delegate BacTrackBatteryVoltage:num];

        } else if (msg[0]==0x85) {
            
            switch (msg[1])
            {
                case UNITS_SETTING_ID:
                {
                    BACtrackUnit units = (BACtrackUnit)msg[2];
                    if ([self.delegate respondsToSelector:@selector(BacTrackUnits:)])
                        [self.delegate BacTrackUnits:units];
                    break;
                }
                case USECOUNT_SETTING_ID:
                {
                    unsigned short uses = (msg[2]&0xff)
                                        + ((msg[3]&0xff) << 8);
                    lastUseCount = [NSNumber numberWithShort:uses];
                    if ([self.delegate respondsToSelector:@selector(BacTrackUseCount:)])
                        [self.delegate BacTrackUseCount:lastUseCount];
                    break;
                }
            }            
        } else {
            fprintf(stderr,"unknown\n");
        }
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(nullable NSError *)error {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error {
}
-(void)continualBACtrackIdleReset
{
}

-(void)checkAllCharacteristics
{
    if (!connected
        && characteristicSerial
        && charFirmware) {
     
        connected = YES;
        
        if ([self.delegate respondsToSelector:@selector(BacTrackConnected:)])
            [self.delegate BacTrackConnected:self.type];
        else if ([self.delegate respondsToSelector:@selector(BacTrackConnected)])
            [self.delegate BacTrackConnected];
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
    
    if (service==serviceSerial) {
        characteristicSerial = (CBCharacteristic *)[service.characteristics objectAtIndex:0];
        [bacTrack setNotifyValue:YES forCharacteristic:characteristicSerial];
        
        [self getBreathalyzerUseCount];
    } else if (service == serviceOAD) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_CHARACTERISTIC_OAD_IDENTIFY]) {
                charIdentify = characteristic;
            }
            else if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_CHARACTERISTIC_OAD_BLOCK]) {
                charBlock = characteristic;
                [bacTrack setNotifyValue:YES forCharacteristic:charBlock];
            }
            else if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_CHARACTERISTIC_OAD_COUNT]) {
                charCount = characteristic;
                [bacTrack setNotifyValue:YES forCharacteristic:charCount];
            }
            else if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_CHARACTERISTIC_OAD_STATUS]) {
                charStatus = characteristic;
                [bacTrack setNotifyValue:YES forCharacteristic:charStatus];
            }

        }
    } else if (service == serviceVersions) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION]) {
                charFirmware = characteristic;
            }
        }
    }
    if (!error) {
        [self checkAllCharacteristics];
        NSLog(@"%@: Characteristics of peripheral found", self.class.description);
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
            if ([service.UUID isEqual:[CBUUID UUIDWithString:C6_SERIAL_GATT_SERVICE_UUID]]) {
                serviceSerial = service;
            
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:C6_SERIAL_GATT_CHAR_UUID],
                                             nil];
            
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS]]) {
                serviceVersions = service;
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION],
                                             nil];
                
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_OAD]]) {
                serviceOAD = service;
                
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_IDENTIFY],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_BLOCK],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_STATUS],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_COUNT],
                                             nil];
                
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }

        }
    }
}

- (void) writeUnitsToDevice:(BACtrackUnit)units
{
    Byte val[3];
    val[0] = WRITE_PERSISTENT_SETTING;
    val[1] = UNITS_SETTING_ID;
    val[2] = 0;
    if (units == BACtrackUnit_mgL)
        val[2] = 1;
    else if (units == BACtrackUnit_permille)
        val[2] = 4;
    else if (units == BACtrackUnit_permilleByMass)
        val[2] = 11;
    else if (units == BACtrackUnit_mg)
        val[2] = 12;
    
    NSData *data = [NSData dataWithBytes:&val length:3];
    [bacTrack writeValue:data forCharacteristic:characteristicSerial type:CBCharacteristicWriteWithResponse];
}

- (void) readUnitsFromDevice
{
    Byte val[2];
    val[0] = READ_PERSISTENT_SETTING;
    val[1] = UNITS_SETTING_ID;
    NSData *data = [NSData dataWithBytes:&val length:2];
    [bacTrack writeValue:data forCharacteristic:characteristicSerial type:CBCharacteristicWriteWithResponse];
}



@end
