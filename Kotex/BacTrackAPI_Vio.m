//
//  BacTrackAPI_Kotex.m
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/9/14.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//

#import "BacTrackAPI_Vio.h"
#import "Helper.h"
#import "Globals.h"
#import "Breathalyzer.h"
#import "BacTrac2SerialProtocol.h"
#import "BacTrackOAD.h"
#import "HeatCountNormalizer.h"

typedef NS_ENUM(NSInteger, VioErrorCode) {
    VioErrorCode_None = 0,
    VioErrorCode_Blow,
    VioErrorCode_Temperature,
    VioErrorCode_LowBattery,
    VioErrorCode_Calibration,
    VioErrorCode_NotCalibration,
    VioErrorCode_Communication,
    VioErrorCode_Inflow,
    VioErrorCode_Sensor,
    VioErrorCode_BacUpperLimit
};


@interface BacTrackAPI_Vio () < CBPeripheralDelegate> {
    CBPeripheral     * bacTrack;
    NSTimer          * timer;
    BOOL               connected;
    BOOL               hasReportedLowBattery;
    
    NSNumber *         lastUseCount;
    
    BacTrac2SerialProtocol *serialController;
    CBCharacteristic *transmitCharacteristic;
    CBCharacteristic *receiveCharacteristic;
    
    NSMutableDictionary *connectedCharacteristic;
    
    uint8_t             latestBatteryLevel;
}
@end

@implementation BacTrackAPI_Vio
@synthesize delegate=_delegate;

+(NSDictionary *) servicesDictionary
{
    NSArray * hardwareCharacteristics = [NSArray arrayWithObjects:
                                 [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_HARDWARE_VERSION],
                                 [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION],
                                 [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_SOFTWARE_VERSION],
                                 nil];

    NSArray * batteryCharacteristics = [NSArray arrayWithObjects:
                                 [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY],
                                 nil];

    NSArray * serialCharacteristics = [NSArray arrayWithObjects:
                                 [CBUUID UUIDWithString:VIO_BACTRACK_CHARACTERISTIC_SERIAL_TRANSMIT],
                                 [CBUUID UUIDWithString:VIO_BACTRACK_CHARACTERISTIC_SERIAL_RECEIVE],
                                 nil];
    
    
    NSArray * oadCharacteristics = [NSArray arrayWithObjects:
                                 [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_ONE],
                                 [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_OAD_TWO],
                                 nil];

    
    //XXX make static
    NSDictionary *serviceCharicteristicsMapping = @{
        [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS] : hardwareCharacteristics,
        [CBUUID UUIDWithString:VIO_BACTRACK_SERVICE_ONE] : serialCharacteristics,
        [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_BATTERY] : batteryCharacteristics,
        [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_OAD] : oadCharacteristics
        };
    return serviceCharicteristicsMapping;
}


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
        latestBatteryLevel = 15;
        connectedCharacteristic = [NSMutableDictionary dictionaryWithCapacity:7];
        transmitCharacteristic = NULL;
        serialController = [[BacTrac2SerialProtocol alloc] init];
    }
    return self;
}

-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral
{
    bacTrack = peripheral;
    bacTrack.delegate = self;
    self.delegate = delegate;
    return [self init];
}


-(void)configurePeripheral
{
    // Discover services
    NSArray * services = [[BacTrackAPI_Vio servicesDictionary] allKeys];

    bacTrack.delegate = self;
    [bacTrack discoverServices:services];
}

-(void)disconnect
{
    //cleanup, notify delegate and get out
    [timer invalidate];
    timer = nil;
    serialController = nil;
    [connectedCharacteristic removeAllObjects];
    
    if ([self.delegate respondsToSelector:@selector(BacTrackDisconnected)]) {
        [self.delegate BacTrackDisconnected];
    }
    
    bacTrack = nil;
}

#pragma mark -
#pragma mark Helper Methods
/****************************************************************************/
/*								Helper Methods                              */
/****************************************************************************/

-(void)notifyDelegateOfLowBattery{
    if(!hasReportedLowBattery){
        if ([self.delegate respondsToSelector:@selector(BacTrackBatteryVoltage:)])
            [self.delegate BacTrackBatteryVoltage:@(3.9)];
    }
    
    if ([self.delegate respondsToSelector:@selector(BacTrackBatteryVoltage:)])
        [self.delegate BacTrackBatteryVoltage:@(3.59)];
    hasReportedLowBattery = TRUE;
}
- (void)triggerReadForCharacteristic:(NSString *)characteristicUUID
{
    CBCharacteristic *cha = [connectedCharacteristic objectForKey:characteristicUUID];
    
    //check we get a characterisitic and that backtrack is connected.
    if (cha && bacTrack.state == CBPeripheralStateConnected) {
        [bacTrack readValueForCharacteristic:cha];
    }
}

- (void)transmitPacket:(NSData *)packet
{
    UInt8 command;
    [packet getBytes:&command range:(NSRange){3,1}];
    NSLog(@"OUTGOING MESSAGE-> cmd:0x%x   , msg:%@",command,[packet description]);
    
    if (packet && bacTrack.state == CBPeripheralStateConnected) {
        [bacTrack writeValue:packet forCharacteristic:transmitCharacteristic type:CBCharacteristicWriteWithoutResponse];
    }
}

-(void) handleNewMessage:(BacTrac2Message *)message
{
    if (message.command == BT2CommandStatusReportResponse)
    {
        StatusReportResponse res = [message statusReportResponse];
        switch (res.activity_state)
        {
            case BT2ActivityStateIdle:
                NSLog(@"Activity:idle");
                break;
            case BT2ActivityStateCountDown:
                NSLog(@"Activity:Count down");
                if ([self.delegate respondsToSelector:@selector(BacTrackCountdown:executionFailure:)])
                {
                    NSLog(@"Heat Count: %@",[NSNumber numberWithInt:res.heat_count]);
                    NSNumber* normalizedCount = [HeatCountNormalizer normalizeHeatCount:@(res.heat_count)];
                    NSLog(@"Normalized Heat Count: %@",normalizedCount);
                    [self.delegate BacTrackCountdown:normalizedCount executionFailure:FALSE];
                }
                break;
            case BT2ActivityStateReadyForBlow:
                NSLog(@"Activity:Ready for blow");
                [timer invalidate];
                timer = nil;
                timer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(blowErrorTimedout) userInfo:nil repeats:NO];
                
                if ([self.delegate respondsToSelector:@selector(BacTrackStart)])
                {
                    [self.delegate BacTrackStart];
                }
                break;
            case BT2ActivityStateBlowInProgress:
                NSLog(@"Activity:Blow in progress");
                [timer invalidate];
                timer = nil;
                
                if ([self.delegate respondsToSelector:@selector(BacTrackBlow)])
                {
                    [self.delegate BacTrackBlow];
                }
                break;
            case BT2ActivityStateAnalyzing:
                NSLog(@"Activity:Analyzing");
                if ([self.delegate respondsToSelector:@selector(BacTrackAnalyzing)])
                {
                    [self.delegate BacTrackAnalyzing];
                }
                break;
            case BT2ActivityStateIdleWithValidBAC:
                NSLog(@"Activity: Idle+BAC");
                if ([self.delegate respondsToSelector:@selector(BacTrackAnalyzing)])
                {
                    [self.delegate BacTrackAnalyzing];
                }
                if ([self.delegate respondsToSelector:@selector(BacTrackResults:)])
                {
                    [self.delegate BacTrackResults:(res.bac_reading/10000.0f)];
                }
                break;
            case BT2ActivityStateCalibrating:
                break;
            case BT2ActivityStatePoweringDown:
                break;
            default:
                break;
        }
        
        NSDictionary* statusdict = @{
                                     @"State": @(res.activity_state),
                                     @"Battery": @(res.battery_level),
                                     @"Heat Count": @(res.heat_count),
                                     @"BAC Reading": @(res.bac_reading)
                                     };
        
        [[NSNotificationCenter defaultCenter]
         postNotificationName:@"Vio_Status_Notification"
         object:self
         userInfo:statusdict];
        
        latestBatteryLevel = res.battery_level;
        if(res.battery_level == 0)
        {
            [self notifyDelegateOfLowBattery];
        }
        
    }
    else if (message.command == BT2CommandDeviceIDResponse)
    {
        // Currently unused
        // DeviceIdResponse res = [message deviceIdResponse];
    }
    else if (message.command == BT2CommandErrorReportResponse)
    {
        ErrorReportResponse err = [message errorReportResponse];

        UInt8 MobileErrorCode;
        switch ((VioErrorCode)err.error_code)
        {
            case VioErrorCode_None:
                MobileErrorCode = 0xff;
                break;
            case VioErrorCode_Blow:
                MobileErrorCode = MOBILE__ERROR_BLOW_ERROR;
                break;
            case VioErrorCode_Temperature:
                MobileErrorCode = MOBILE__ERROR_OUT_OF_TEMPERATURE;
                break;
            case VioErrorCode_LowBattery:
                //Do not return the error code for low battery. Just inform the delegate that battery is below x%
                [self notifyDelegateOfLowBattery];
                return;
                break;
            case VioErrorCode_Calibration:
                MobileErrorCode = MOBILE__ERROR_CALIBRATION_FAIL;
                break;
            case VioErrorCode_NotCalibration:
                MobileErrorCode = MOBILE__ERROR_NOT_CALIBRATED;
                break;
            case VioErrorCode_Communication:
                MobileErrorCode = MOBILE__ERROR_COM_ERROR;
                break;
            case VioErrorCode_Inflow:
//                MobileErrorCode = MOBILE__ERROR_INFLOW_ERROR;
                MobileErrorCode = MOBILE__ERROR_BLOW_ERROR;  
                break;
            case VioErrorCode_Sensor:
                MobileErrorCode = ERROR_SENSOR;
                break;
            case VioErrorCode_BacUpperLimit:
                MobileErrorCode = ERROR_BAC_UPPER_LIMIT;
                break;
            default:
                break;
        }
        
        NSError *error = [NSError errorWithDomain:@"Breathalyzer error" code:MobileErrorCode userInfo:nil];

        if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]){
            [self.delegate BacTrackBreathalyzerError:MobileErrorCode withTemperature:err.error_info];
        }
        if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
            [self.delegate BacTrackError:error];
        }
        
    }
    else if (message.command == BT2CommandSettingReadResponse)
    {
        SettingReportResponse set = [message settingReportResponse];
        
        switch (set.param_id)
        {
            case BT2ParamUseCount:
                lastUseCount = [NSNumber numberWithUnsignedInt:set.data];
                if ([self.delegate respondsToSelector:@selector(BacTrackUseCount:)])
                {
                    [self.delegate BacTrackUseCount:lastUseCount];
                }
                break;
                
            case BT2ParamBlowTime:
                if ([self.delegate respondsToSelector:@selector(BacTrackBlowTimeSetting:)])
                {
                    [self.delegate BacTrackBlowTimeSetting:[NSNumber numberWithUnsignedChar:set.status]];
                }
                break;
            default:
                //xxx
                break;
        }

    }
    else if (message.command == BT2CommandSettingWriteResponse)
    {
        SettingReportResponse set = [message settingReportResponse];
        
        switch (set.param_id)
        {
            case BT2ParamBlowTime:
                if ([self.delegate respondsToSelector:@selector(BacTrackSetBlowTimeAcknowledgement:)])
                {
                    [self.delegate BacTrackSetBlowTimeAcknowledgement:YES];
                }
                break;
            case BT2ParamButtonStatusChangeReport:
                //not sure what if anything to do with this
                break;
            default:
                //send error for writing to readonly param_id
                break;
        }
    
    }
    else if (message.command == BT2CommandSettingChangeReportResponse)
    {
        SettingReportResponse set = [message settingReportResponse];
        switch (set.param_id)
        {
            case BT2ParamButtonStatus:
                //Param button status update successful.
                break;
            default:
                break;
        }

    }
    else if (message.command == BT2CommandDeviceControlResponse)
    {
        SettingReportResponse set = [message settingReportResponse];
       
        switch ((int)set.param_id)
        {
            case 0:
                //start sequence
                break;
            case 1:
                //cancel sequence
                break;
            case 2:
                //shut down.
                break;
            default:
                break;
        }
        
    }
}

-(void)blowErrorTimedout
{
    [timer invalidate];
    timer = nil;
    
    NSError *error = [NSError errorWithDomain:@"Breathalyzer time out error" code:MOBILE__ERROR_TIME_OUT userInfo:nil];

    if ([self.delegate respondsToSelector:@selector(BacTrackBreathalyzerError:withTemperature:)]) {
        [self.delegate BacTrackBreathalyzerError:MOBILE__ERROR_TIME_OUT withTemperature:0];
    }
    if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
        [self.delegate BacTrackError:error];
    }
}


#pragma mark -
#pragma mark BacTrackAPI Methods
/****************************************************************************/
/*								BacTrackAPI Methods                             */
/****************************************************************************/

-(void)getFirmwareVersion
{
    [self triggerReadForCharacteristic:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION];
}

-(BOOL)startCountdown
{
    //if errors, return NO;

    NSData* packet = [serialController generateDeviceControlRequest:BT2DeviceStartSequence];
    [self transmitPacket:packet];
    return YES;
}

-(void)getBreathalyzerUseCount
{
    NSData* packet = [serialController generateSettingReadRequest:BT2SettingUseCount];
    [self transmitPacket:packet];
}

-(void)disableBreathalyzerAdvertising
{
    NSAssert(0, @"vio does not implement this");
}

-(void)setBreathalyzerProtectionBit:(BOOL)enabled {

    if ([self.delegate respondsToSelector:@selector(BacTrackProtectionBit:)]) {
        [self.delegate BacTrackProtectionBit:@YES];   
    }
}

-(void)resetBACTimeout
{
    //Cancel the sequence, the restart after a short delay.
   /* NSData* packet = [serialController generateDeviceControlRequest:BT2DeviceCancelSequence];
    [self transmitPacket:packet];
    [self performSelector:@selector(startCountdown) withObject:nil afterDelay:1];
    */
}

-(void)setBreathalyzerTransmitPower:(NSNumber*)power
{
    NSAssert(0, @"vio does not implement this");
}

-(void)getBreathalyzerTransmitPower
{
    NSAssert(0, @"vio does not implement this");
}

-(void)getBreathalyzerBatteryVoltage
{
    if(latestBatteryLevel == 0)
    {
        [self notifyDelegateOfLowBattery];
    }
    else
    {
        if ([self.delegate respondsToSelector:@selector(BacTrackBatteryVoltage:)])
            [self.delegate BacTrackBatteryVoltage:@(9.99)]; //a ridiculously high voltage because we're making up that it's "full battery"
    }

//    [self triggerReadForCharacteristic:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY];
}

-(void)getBreathalyzerBatteryLevel
{
    [self getBreathalyzerBatteryVoltage];
}

-(void)getBreathalyzerSerialNumber
{
    NSAssert(0, @"vio does not implement this");    
}

-(void)turnOnLedOne:(BOOL)on
{
    
}
-(void)turnOnLedTwo:(BOOL)on
{
    
}

-(void)pulseLedOne:(BOOL)on
{
    
}

-(void)pulseLedTwo:(BOOL)on
{
    
}

-(void)setLedOneIntensity:(Byte)intensity
{
    
}

-(void)setLedTwoIntensity:(Byte)intensity
{
    
}

-(BOOL)setBreathalyzerBlowTimeSetting:(NSNumber*)seconds
{
    uint8_t tValue = (uint8_t) [seconds shortValue];
    //sanity checking time value.
    if (tValue < 1 || tValue > 10) {
        return NO;
    }
    NSData *data = [NSData dataWithBytes:&tValue length:sizeof(tValue)];
    
    NSData* packet = [serialController generateSettingWriteRequest:BT2SettingBlowTime value:data];
    [self transmitPacket:packet];
    return  YES;
}

-(void)getBreathalyzerBlowTimeSetting
{
    NSData* packet = [serialController generateSettingReadRequest:BT2SettingBlowTime];
    [self transmitPacket:packet];
}

-(BOOL)setBreathalyzerBlowLevelSetting:(UInt8)setting
{
    NSAssert(0, @"vio does not implement this");
    return NO;
}

-(void)getBreathalyzerBlowLevelSetting
{
    NSAssert(0, @"vio does not implement this");
}

-(void)getBreathalyzerRSSI
{
    [bacTrack readRSSI];
}


-(void)flashBreathalyzerLEDs:(Breathalyzer*)breathalyzer withTimeout:(NSTimeInterval)timeout
{
    
}

-(BOOL)isProtectionOn
{
    return NO;
}

-(void)startCalibration
{
    NSAssert(0, @"vio does not implement this");
}

-(void)requestCalibrationCoefficients
{
    
}

-(void)performFactoryReset
{
    
}

// Requests the last cached use count from the breathalyzer
-(void)getLastUseCount
{
    NSAssert(0, @"vio does not implement this");
}


-(BOOL)checkForNewFirmware:(NSString*)newFirmwareVersion
{
    NSAssert(0, @"vio does not implement this");
    return NO;
}

-(BACtrackReturnType)updateFirmwareWithImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath
{
    NSAssert(0, @"vio does not implement this");
    return BACtrackReturnFalse;
}

-(void)cancelUpdateFirmware
{
    NSAssert(0, @"vio does not implement this");
}

#pragma mark -
#pragma mark CBPeripheralDelegate
/****************************************************************************/
/*			     CBPeripheralDelegate protocol methods beneeth here         */
/****************************************************************************/

-(void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(BacTrackUpdatedRSSI:)])
    {
        [self.delegate BacTrackUpdatedRSSI:peripheral.RSSI];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(nonnull NSNumber *)RSSI error:(nullable NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(BacTrackUpdatedRSSI:)])
        [self.delegate BacTrackUpdatedRSSI:RSSI];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (!error) {
        //NSLog(@"UpdateValueForCharacteristic: %@,  %@", characteristic.UUID, characteristic.value);
        
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:VIO_BACTRACK_CHARACTERISTIC_SERIAL_RECEIVE]]) {
            //process new serial message
            //NSLog(@"MESSAGE RECEIVED: %@",characteristic.value);
            BacTrac2Message *message = [serialController processNewPacket:characteristic.value];
            
            //this should probably be refactored to happen inside the serial controller.
            if (message) {
                [self handleNewMessage: message];
            }
            
        } else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY]]) {
            // A 8 bit value that represents battery voltage range 2.8V(0x00) to 4.3V (0xFF)
/*            Byte value;
            NSData * data = characteristic.value;
            [data getBytes:&value length:sizeof(value)];
            
            CGFloat voltage = 3.0f + ((4.2f - 3.0f) * (value * 0.01));
            NSNumber * number = [NSNumber numberWithFloat:voltage];
            if ([self.delegate respondsToSelector:@selector(BacTrackBatteryVoltage:)])
                [self.delegate BacTrackBatteryVoltage:number];
 */
        } else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION]]) {
            NSString * version = [[NSString alloc] initWithData:characteristic.value encoding:NSASCIIStringEncoding];
            
            if ([self.delegate respondsToSelector:@selector(BacTrackFirmwareVersion:)]) {
                [self.delegate BacTrackFirmwareVersion:version];
            }
        }
    }
    else {
        NSLog(@"%@: UpdateValueForCharacteristic failed!", self.class.description);
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (!error) {
        //XXX introspect characteristic name
        NSLog(@"%@: didWriteValueForCharacteristic succeeded UUID: %@", self.class.description, characteristic.UUID);
    }
    else {
        NSLog(@"%@: didWriteValueForCharacteristic failed! UUID: %@", self.class.description, characteristic.UUID);
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

- (void)resetNotify:(CBCharacteristic *)characteristic
{
    [bacTrack readValueForCharacteristic:characteristic];
    [self performSelector:@selector(resetNotify:) withObject:characteristic afterDelay:1];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (!error) {
        NSLog(@"%@: Characteristics of peripheral found", self.class.description);

        //iterate through all discovered charicteristics.
        NSLog(@"Service: %@", service.UUID);
        for (CBCharacteristic * characteristic in service.characteristics) {
            NSLog(@"Characteristic: %@", characteristic.UUID);
            
            //store characteristic for later use
//            [connectedCharacteristic setObject:characteristic forKey:[Helper CBUUIDToString:characteristic.UUID]];

            /*
            //XXX are we getting battery from here or from the serial?
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_BATTERY]]) {
                NSLog(@"Subscripe to characteristric: %@", characteristic.UUID);
                [bacTrack setNotifyValue:YES forCharacteristic:characteristic];
            }
            */
            // Check for Serial Characteristic and setup notification
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:VIO_BACTRACK_CHARACTERISTIC_SERIAL_RECEIVE]]) {
                NSLog(@"Subscripe to characteristric: %@", characteristic.UUID);
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                [self performSelector:@selector(resetNotify:) withObject:characteristic afterDelay:1];
                receiveCharacteristic = characteristic;
            }


            
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:VIO_BACTRACK_CHARACTERISTIC_SERIAL_TRANSMIT]]) {
                NSLog(@"Start serial controller for characteristric: %@", characteristic.UUID);
                transmitCharacteristic = characteristic;
            }
             
        }
        
        // TODO: Implement BacTrackDidConnect
        
        if (!connected && transmitCharacteristic && receiveCharacteristic)
        { // only connect if not connected and we've got all the characteristics.
            connected = YES;

            // Connect normally
            if ([self.delegate respondsToSelector:@selector(BacTrackConnected:)])
                [self.delegate BacTrackConnected:BACtrackDeviceType_Vio];
            else if ([self.delegate respondsToSelector:@selector(BacTrackConnected)])
                [self.delegate BacTrackConnected];
        }
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
            NSLog(@"Service: %@", service.UUID);

            if([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS]])
                continue;
            
            // Pull characteristics from our dictionary.
            NSArray * characteristics = [[BacTrackAPI_Vio servicesDictionary] objectForKey:service.UUID];
            
            // Find characteristics of service
            [bacTrack discoverCharacteristics:characteristics forService:service];

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
