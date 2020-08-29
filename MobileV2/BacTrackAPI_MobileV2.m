//
//  BacTrackAPI_MobileV2.h
//  BacTrackManagement
//
//  Created by Louis Gorenfeld on 9/24/19
//  Copyright (c) 2019 KHN Solutions LLC. All rights reserved.
//
// Based on the C6/C8 module

#import "BacTrackAPI_MobileV2.h"
#import "Helper.h"
#import "Globals.h"
#import "Breathalyzer.h"
#import "BacMessage.h"
#import "BacTrackOAD.h"

@interface BacTrackAPI_MobileV2 () <CBPeripheralDelegate> {
    CBPeripheral     * bacTrack;
    CBService        * serviceBreath;
    CBService        * serviceGeneric;
    CBService        * serviceVersions;
    CBService        * serviceBattery;
    CBService        * serviceOAD;
    
    // DAtech service characteristics (nRF52810)
    CBCharacteristic * charBreathTx;
    CBCharacteristic * charBreathRx;

    // BACtrack service characteristics
    CBCharacteristic * charGenericTx;
    CBCharacteristic * charGenericRx;
    
    CBCharacteristic * charIdentify;
    CBCharacteristic * charBlock;
    CBCharacteristic * charCount;
    CBCharacteristic * charStatus;
    CBCharacteristic * charFirmware;
    CBCharacteristic * charSerial;
    CBCharacteristic * charBatteryVoltage;
    CBCharacteristic * charAdvertising;
        
    BOOL               connected;
    int                prevLED1State;
    int                prevLED2State;

    UInt8 commandAwaitingAck;
    UInt8 powerStateAwaitingAck;
    
    NSData           * firmwareData;

    NSNumber *         lastUseCount;
    
    float              lastBatteryVoltage;
    NSInteger          batteryThresholdIndex;
}

@end

@implementation BacTrackAPI_MobileV2
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
    NSArray * services = [NSArray arrayWithObjects:[CBUUID UUIDWithString:MOBILEV2_BREATH_SERVICE_UUID],
                                                   [CBUUID UUIDWithString:MOBILEV2_GENERIC_SERVICE_UUID],
                                                   [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_OAD],
                                                   [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS],
                                                   [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_BATTERY],
                                                    nil];
    bacTrack.delegate = self;
    [bacTrack discoverServices:services];
}


/// Cleans all characteristics and services
-(void)peripheralDisconnected:(CBPeripheral*)peripheral
{
    connected = NO;
    lastUseCount = nil;
    charBreathRx = nil;
    charBreathTx = nil;
    charGenericTx = nil;
    charGenericRx = nil;
    
    bacTrack = nil;
}


-(BOOL)startCountdown
{
    Byte val[4];
    val[0] = MOBILE__SOF;
    val[1] = MOBILE__COMMAND_TRANSMIT_POWERSTATE;
    val[2] = 0x03;
    val[3] = MOBILE__EOF;
    NSData *data = [NSData dataWithBytes:&val length:4];
    [bacTrack writeValue:data forCharacteristic:charBreathRx type:CBCharacteristicWriteWithResponse];

    commandAwaitingAck = MOBILE__COMMAND_TRANSMIT_POWERSTATE;
    powerStateAwaitingAck = 0x03;

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
    NSLog(@"OAD not yet supported for MobileV2");
    return false;
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
    // OAD not fully implemented
}



-(void)getBreathalyzerUseCount
{
    // TODO: Do we send a request for the device to send us a Use Count like this?
    Byte val[1];
    val[0] = 0x02;
    NSData *data = [NSData dataWithBytes:&val length:1];
    [bacTrack writeValue:data forCharacteristic:charGenericRx type:CBCharacteristicWriteWithResponse];
}

-(void)getBreathalyzerSerialNumber
{
    if (charSerial)
        [bacTrack readValueForCharacteristic:charSerial];
}

-(void)getBreathalyzerBatteryVoltage
{
    if (charBatteryVoltage)
        [bacTrack readValueForCharacteristic:charBatteryVoltage];
}

-(void)getBreathalyzerBatteryLevel
{
    [self getBreathalyzerBatteryVoltage];
}

-(void)getFirmwareVersion
{
    if (charFirmware)
        [bacTrack readValueForCharacteristic:charFirmware];
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
    Byte val[3] = { MOBILE__SOF, 0x92, MOBILE__EOF };
    NSData *data = [NSData dataWithBytes:&val length:3];
    [bacTrack writeValue:data forCharacteristic:charBreathRx type:CBCharacteristicWriteWithResponse];
}


- (void)pulseLedOne:(BOOL)on {
    if (on)
    {
        Byte val[2];
        val[0] = 0x01;
        val[1] = 0x01;
        
        NSData *data = [NSData dataWithBytes:&val length:2];
        [bacTrack writeValue:data forCharacteristic:charGenericRx type:CBCharacteristicWriteWithResponse];
    }
    else
    {
        [self setLedOneIntensity:prevLED1State];
    }
}

- (void)pulseLedTwo:(BOOL)on {
    if (on)
    {
        Byte val[2];
        val[0] = 0x01;
        val[1] = 0x02;
        
        NSData *data = [NSData dataWithBytes:&val length:2];
        [bacTrack writeValue:data forCharacteristic:charGenericRx type:CBCharacteristicWriteWithResponse];
    }
    else
    {
        [self setLedTwoIntensity:prevLED2State];
    }
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

- (void)setLedOneIntensity:(Byte)intensity {
    Byte val[3];
    val[0] = 0x00;
    val[1] = 0x01;
    val[2] = intensity;
    
    NSData *data = [NSData dataWithBytes:&val length:3];
    [bacTrack writeValue:data forCharacteristic:charGenericRx type:CBCharacteristicWriteWithResponse];
    prevLED1State = intensity;
}


- (void)setLedTwoIntensity:(Byte)intensity {
    Byte val[3];
    val[0] = 0x00;
    val[1] = 0x02;
    val[2] = intensity;
    
    NSData *data = [NSData dataWithBytes:&val length:3];
    [bacTrack writeValue:data forCharacteristic:charGenericRx type:CBCharacteristicWriteWithResponse];
    prevLED2State = intensity;
}


- (void)startCalibration {
    Byte val[3];
    val[0] = MOBILE__SOF;
    val[1] = MOBILE__COMMAND_TRANSMIT_CALIBRATION_START;
    val[2] = MOBILE__EOF;
    NSData *data = [NSData dataWithBytes:&val length:3];
    [bacTrack writeValue:data forCharacteristic:charBreathRx type:CBCharacteristicWriteWithResponse];

    commandAwaitingAck = MOBILE__COMMAND_TRANSMIT_CALIBRATION_START;
}


- (void)turnOnLedOne:(BOOL)on {
    [self setLedOneIntensity:on? 255 : 0];
}


- (void)turnOnLedTwo:(BOOL)on {
    [self setLedTwoIntensity:on? 255 : 0];
}




#pragma mark -
#pragma mark Private Methods
/****************************************************************************/
/*								Private Methods                             */
/****************************************************************************/

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
        [self.delegate BacTrackBatteryLevel:[NSNumber numberWithInt:((int)batteryThresholdIndex)]];
}

- (void)handleBreathTx:(NSData*)originalMessage
{
    // This is largely copied from BacTrackAPI_Mobile v1
    
    BacMessage* receivedbacmessage = [[BacMessage alloc] init];
    
    //This is size 20 because that currently is the max size of the entire message. It will indefinitely be able to contain the message data
    UInt8 databuffer[20];
    
    if([BacMessage parseMessage:originalMessage intoBacMessage:receivedbacmessage] == TRUE){
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
                        // While the mobileV1 starts its own timer to look for timeouts here, we should look for PROTOCOL_ERROR_TIMEOUT
                    
                        if ([self.delegate respondsToSelector:@selector(BacTrackStart)])
                            [self.delegate BacTrackStart];
                        break;
                    case MOBILE__STATUS_BLOW:
                        if ([self.delegate respondsToSelector:@selector(BacTrackBlow:)])
                            [self.delegate BacTrackBlow:[NSNumber numberWithFloat:(float)(databuffer[3])/5.0f]];
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
                [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_ERROR_DATALENGTH];
                                
                if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
                    [self.delegate BacTrackBreathalyzerError:databuffer[0] withTemperature:databuffer[1]];
                } else if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
                    [self.delegate BacTrackError:[NSError errorWithDomain:@"Breathalyzer error" code:databuffer[0] userInfo:nil]];
                }
                
                break;
//            case MOBILE__COMMAND_RECEIVE_BLOW_SETTING:            // absent from V2 spec
//                break;
            case MOBILE__COMMAND_RECEIVE_CALIBRATION_STATUS:
                [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_CALIBRATION_STATUS_DATALENGTH];
            
                if ([self.delegate respondsToSelector:@selector(BacTrackCalibrationStatus: withHeatCount:)])
                    [self.delegate BacTrackCalibrationStatus:databuffer[0] withHeatCount:[NSNumber numberWithUnsignedChar:databuffer[1]]];
                break;
            case MOBILE__COMMAND_RECEIVE_CALIBRATION_RESULTS_V2:
                [receivedbacmessage.data getBytes:databuffer length:MOBILE__COMMAND_RECEIVE_CALIBRATION_RESULTS_DATALENGTH];
                
                if ([self.delegate respondsToSelector:@selector(BacTrackCalibrationResults: withResultStatus: withHeatCount:)])
                    [self.delegate BacTrackCalibrationResults:databuffer[0] withResultStatus:databuffer[1] withHeatCount:[NSNumber numberWithUnsignedChar:databuffer[2]]];
                break;

            default:
                NSLog(@"Unhandled breath tx");
                break;
        }
    }
}

#define OAD_BLOCK_SIZE 16
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (characteristic==charFirmware)    {
        NSString * version = [[NSString alloc] initWithData:characteristic.value encoding:NSASCIIStringEncoding];
        
        if ([self.delegate respondsToSelector:@selector(BacTrackFirmwareVersion:)])
            [self.delegate BacTrackFirmwareVersion:version];
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
    }
    else if (characteristic==charSerial)
    {
        NSData *data = characteristic.value;
        if ([self.delegate respondsToSelector:@selector(BacTrackSerial:)])
        {
            [self.delegate BacTrackSerial:[NSMutableString stringWithUTF8String:[data bytes]]];
        }
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
        // TODO: This is for OAD (not the breathalyzer use count), and is not fully implemented yet
    }
    else if ([characteristic isEqual:charBatteryVoltage]) {
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
    else if (characteristic==charGenericTx)
    {
        Byte *msg = (Byte *)characteristic.value.bytes;
        if (msg[0] == 0x82)
        {
            lastUseCount = [NSNumber numberWithShort:(msg[1]&0xff) + ((msg[2]>>8)&0xff)];
        }
    }
    else if (characteristic==charBreathTx)
    {
        [self handleBreathTx:characteristic.value];
    }
    else
    {
        NSLog(@"WARNING: Unknown value for characteristic");
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(nullable NSError *)error {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error {
    NSLog(@"did updatenotificationstate");
}
-(void)continualBACtrackIdleReset
{
}

-(void)checkAllCharacteristics
{
    if (!connected
        && charBreathRx
        && charBreathTx
        && charGenericRx
        && charGenericTx
        && charBatteryVoltage
        && charSerial
        && charFirmware) {
            connected = YES;
            
            // Connect normally
            if ([self.delegate respondsToSelector:@selector(BacTrackConnected:)])
                [self.delegate BacTrackConnected:BACtrackDeviceType_MobileV2];
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
    
    if (service==serviceBreath) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID.UUIDString isEqualToString:MOBILEV2_BREATH_GATT_TX_CHAR_UUID]) {
                charBreathTx = characteristic;
            }
            else if ([characteristic.UUID.UUIDString isEqualToString:MOBILEV2_BREATH_GATT_RX_CHAR_UUID]) {
                charBreathRx = characteristic;
            }
        }
        [bacTrack setNotifyValue:YES forCharacteristic:charBreathTx];
    } else if (service==serviceGeneric) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID.UUIDString isEqualToString:MOBILEV2_GENERIC_GATT_TX_CHAR_UUID]) {
                charGenericTx = characteristic;
            }
            else if ([characteristic.UUID.UUIDString isEqualToString:MOBILEV2_GENERIC_GATT_RX_CHAR_UUID]) {
                charGenericRx = characteristic;
            }
        }
        [bacTrack setNotifyValue:YES forCharacteristic:charGenericRx];
    } else if (service == serviceOAD) { // I think we will have to change this for V2
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
            else if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_CHARACTERISTIC_SERIAL]) {
                charSerial = characteristic;
                [bacTrack setNotifyValue:YES forCharacteristic:charSerial];
            }
        }
    } else if (service == serviceBattery) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID.UUIDString isEqualToString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY]) {
                charBatteryVoltage = characteristic;
                [bacTrack setNotifyValue:YES forCharacteristic:charSerial];
            }
        }
    }
    if (!error) {
        NSLog(@"%@: Characteristics of peripheral found", self.class.description);
        [self checkAllCharacteristics];        
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
            if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILEV2_BREATH_SERVICE_UUID]]) {
                serviceBreath = service;
            
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:MOBILEV2_BREATH_GATT_TX_CHAR_UUID],
                                             [CBUUID UUIDWithString:MOBILEV2_BREATH_GATT_RX_CHAR_UUID],
                                             nil];
            
                
                // Find characteristics of service
                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
            if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILEV2_GENERIC_SERVICE_UUID]]) {
                serviceGeneric = service;
                
                // Discover characteristics
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:MOBILEV2_GENERIC_GATT_TX_CHAR_UUID],
                                             [CBUUID UUIDWithString:MOBILEV2_GENERIC_GATT_RX_CHAR_UUID],
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
                // Check this for V2
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
            if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_BATTERY]]) {
                serviceBattery = service;
                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY],
                                             nil];

                [bacTrack discoverCharacteristics:characteristics forService:service];
            }
        }
    }
}

@end
