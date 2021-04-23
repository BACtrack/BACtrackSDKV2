//
//  BacTrackAPI_Skyn.m
//  BACtrack
//
//  Created by Zach Saul on 6/12/18.
//  Copyright © 2018 KHN Solutions. All rights reserved.
//

#import "BacTrackAPI_Skyn.h"

#define SKYN_EVENT_CODE_POWER_RESTORED 0x0B
#define SKYN_EVENT_CODE_TIME_SYNC 0x0C

@interface BacTrackAPI_Skyn () <CBPeripheralDelegate>
{
  CBPeripheral *mPeripheral;

  CBService        * mServiceSerial;
  CBService        * mServiceVersions;
  CBCharacteristic * mCharacteristicSerialRx;
  CBCharacteristic * mCharacteristicSerialTx;
  CBCharacteristic * mCharacteristicFirmwareRevision;
  CBCharacteristic * mCharacteristicHardwareRevision;
  CBCharacteristic * mCharacteristicSerialNumber;
  long               mRecordFetchChunkSize;
  long               mTotalNumRecordsToFetch;
  Boolean            mIsRealTimeMode;
  NSString         * mFilePath;
  int                mWritten;
  int                mLastChunkSize;
  uint32_t           mCounter;
  uint32_t           mCounterWritten;
  int                mNonSamplePointRecordCount;
  NSString         * mFirmwareVersion;        // last-read firmware revision

  // Results are split into chunks that begin at a timestamp and
  // occur at a given samplerate
  uint32_t           mChunkTimestamp;
  uint32_t           mChunkSampleRate;

  // True if we are waiting on the timestamp to say we're connected
  // This will cause iOS to ask to pair with the device if needed
  // (read/write from encrypted characteristic forces this. There
  // is no equivalent CoreBluetooth call)
  BOOL               mFinalizingConnection;
}

@property (readwrite)NSString *hardwareRevision;

@end

@implementation BacTrackAPI_Skyn

-(instancetype)init
{
  if (self = [super init]) {
    mBatchResults = [[NSMutableArray alloc] init];
    mCalibrationPoints = [[NSMutableDictionary alloc] init];
    mNonSamplePointRecordCount = 0;
  }

  return self;
}

-(instancetype)initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral
{
  if (self = [self init]) {
    mPeripheral = peripheral;
    self.delegate = delegate;
    mPeripheral.delegate = self;
  }

  return self;
}

- (void) configurePeripheral
{
  if (![self isConnectedOrConnecting]) {
    return;
  }
  // Discover services
  NSArray * services = @[
    [CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS],
    [CBUUID UUIDWithString:SKYN_SERIAL_GATT_SERVICE_UUID]
  ];
  mPeripheral.delegate = self;

  [mPeripheral discoverServices:services];
}

- (void) startCountdown
{
  return;
}

- (BOOL)isConnectedOrConnecting {
  CBPeripheralState state = mPeripheral.state;
  BOOL isConnectedOrConnecting = state == CBPeripheralStateConnected || state == CBPeripheralStateConnecting;
  return isConnectedOrConnecting;
}

- (void)disconnect
{
  const Byte disconnectMsg[] = {0x07};
  NSData *data = [NSData dataWithBytes:&disconnectMsg length:1];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];

  mPeripheral = nil;
}

-(void)peripheralDisconnected:(CBPeripheral*)peripheral
{
  mPeripheral = nil;
  mServiceSerial = nil;
  mServiceVersions = nil;
  mCharacteristicSerialRx = nil;
  mCharacteristicSerialTx = nil;
  mCharacteristicFirmwareRevision = nil;
  mCharacteristicHardwareRevision = nil;
  mCharacteristicSerialNumber = nil;
  mBatchResults = nil;
  mFilePath = nil;
  mCalibrationPoints = nil;
  mChunkSamplePoints = nil;
}

-(void) parseRecords:(Byte *)bytes length:(NSUInteger)length
{
  const Byte TIMESTAMP_AND_SAMPLE_RATE = 0x0;
  const Byte SENSOR_DATA = 0x1;
  const Byte EVENT = 0x2;
  const Byte BATTERY_VOLTAGE = 0x3;

  // bytes[0] is the msg type. The records start at bytes[1].
  // The packet can contain multiple records, each 8 bytes long
  for(int i=1; i<length; i+=8)
  {
    Byte *record = &bytes[i];
    Byte recordType = record[0];

    mCounter += 1;

    switch (recordType) {
      case TIMESTAMP_AND_SAMPLE_RATE:
      {
        uint32_t timestamp = (record[2]&0xff)
        + ((record[3]&0xff)<<8)
        + ((record[4]&0xff)<<16)
        + ((record[5]&0xff)<<24);
        uint16_t sampleRate = (record[6]&0xff) + ((record[7]&0xff)<<8);

        if (!mIsRealTimeMode)
          [self startNewSkynChunkAtTimestamp:timestamp andSampleRate:sampleRate];

        if ([self.delegate respondsToSelector:@selector(BacTrackSkynTimestamp:sampleRate:)])
          [self.delegate BacTrackSkynTimestamp: timestamp sampleRate: sampleRate];

        mNonSamplePointRecordCount ++;
        break;
      }
      case SENSOR_DATA:
      {
        int alcoholSensorValue = 0;
        int temperatureSensorValue = 0;
        int accelerationMagnitudeSensorValue = 0;

        // Byte 0 was the record type.
        // Byte 1 is reserved.
        // Byte 2-3 is the alcohol sensor value.

        NSData *data = [NSData dataWithBytes:record length:8];
        NSData *alcoholSensorValueChunk = [data subdataWithRange:NSMakeRange(1, 2)];
        NSData *temperatureSensorValueChunk = [data subdataWithRange:NSMakeRange(4, 2)];
        NSData *accelerationMagnitudeSensorValueChunk = [data subdataWithRange:NSMakeRange(6, 2)];
        alcoholSensorValue = CFSwapInt16(*(int*)([alcoholSensorValueChunk bytes]));
//        alcoholSensorValue = (record[3]&0xff<<8) + ((record[2]&0xff));

        // Byte 4-5 is the temp sensor value.
//        temperatureSensorValue = (record[4]&0xff) + ((record[5]&0xff)<<8);
        temperatureSensorValue = CFSwapInt16LittleToHost(*(int*)([temperatureSensorValueChunk bytes]));
        // Byte 6-7 is the accel sensor value.
        accelerationMagnitudeSensorValue = CFSwapInt16LittleToHost(*(int*)([accelerationMagnitudeSensorValueChunk bytes]));
//        accelerationMagnitudeSensorValue = (record[6]&0xff) + ((record[7]&0xff)<<8);

        NSArray *samplePoint = @[[NSNumber numberWithInt:alcoholSensorValue],
                                 [NSNumber numberWithInt:temperatureSensorValue],
                                 [NSNumber numberWithInt:accelerationMagnitudeSensorValue]
        ];

        if (!mIsRealTimeMode)
        {
          mWritten += 1;
          mCounterWritten += 1;

          [mChunkSamplePoints addObject:samplePoint];
        }

        if ([self.delegate respondsToSelector:@selector(BacTrackSkynResultSamplePoint:)])
          [self.delegate BacTrackSkynResultSamplePoint:samplePoint];

        break;
      }
      case EVENT:
      {
        Byte *event = record + 2;
        int eventCode = event[4];
        int eventPayload = event[5];
        int eventTimestamp = (event[0]&0xff)
        + ((event[1]&0xff)<<8)
        + ((event[2]&0xff)<<16)
        + ((event[3]&0xff)<<24);

        if (eventCode == SKYN_EVENT_CODE_TIME_SYNC
            || eventCode == SKYN_EVENT_CODE_POWER_RESTORED)
        {
          // Save time sync, timestamp, and power restored events so we can recover samples from a power outage
          // See p15 of the BACtrack Skyn spec, ver 12/6/2019
          [self saveSkynChunk];

          [mBatchResults addObject:@{SKYN_RESULT_KEY_RECORD_TYPE: SKYN_RECORD_TYPE_EVENT,
                                     SKYN_RESULT_KEY_EVENT_CODE: [NSNumber numberWithInt:eventCode],
                                     SKYN_RESULT_KEY_EVENT_PAYLOAD: [NSNumber numberWithInt:eventPayload],
                                     SKYN_RESULT_KEY_TIMESTAMP: [NSNumber numberWithUnsignedInt:eventTimestamp]
          }];
        }

        mNonSamplePointRecordCount ++;
        break;
      }
      case BATTERY_VOLTAGE:
        mNonSamplePointRecordCount ++;
        break;

      default:
        mNonSamplePointRecordCount ++;
        break;
    }
  }
}

#pragma mark -
#pragma mark CBPeripheralDelegate

-(void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(NSError *)error
{
  if (!error)
  {
    if (self.delegate && [self.delegate respondsToSelector:@selector(BacTrackUpdatedRSSI:)])
      [self.delegate BacTrackUpdatedRSSI:peripheral.RSSI];
  }
  else
  {
    NSLog(@"peripheralDidUpdateRSSI: %@", error);
  }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{

  if (characteristic==mCharacteristicSerialRx)
  {
    const Byte TIMESTAMP_MSG = 0x80;
    const Byte SAMPLERATE_MSG = 0x8B;
    const Byte BATTERY_MSG = 0x82;
    const Byte RECORD_COUNT_MSG = 0x93;
    const Byte RECORDS_MSG = 0x94;
    const Byte REAL_TIME_RECORD_MSG = 0x97;
    const Byte CALIBRATION_POINTS_MSG = 0x85;

    Byte *msg = (Byte *)characteristic.value.bytes;

    switch(msg[0])
    {
      case TIMESTAMP_MSG:
      {
        uint32_t ts = (msg[1]&0xff)
        + ((msg[2]&0xff)<<8)
        + ((msg[3]&0xff)<<16)
        + ((msg[4]&0xff)<<24);
        // This is not part of the record stream; it is the device's reply when we ask what its current timestamp is

        if (mFinalizingConnection)
        {
          mFinalizingConnection = NO;
          if ([self.delegate respondsToSelector:@selector(BacTrackConnected:)])
            [self.delegate BacTrackConnected:self.type];
          else if ([self.delegate respondsToSelector:@selector(BacTrackConnected)])
            [self.delegate BacTrackConnected];
        }

        break;
      }

      case SAMPLERATE_MSG:
      {
        uint16_t sr = (msg[1]&0xff) + ((msg[2]&0xff)<<8);
        // This is not part of the record stream; it is the device's reply when we ask what its current samplerate is
        break;
      }

      case BATTERY_MSG:
      {
        uint16_t mv = (msg[1]&0xff)
        + ((msg[2]&0xff)<<8);
        if ([self.delegate respondsToSelector:@selector(BacTrackBatteryVoltage:)])
          [self.delegate BacTrackBatteryVoltage:[NSNumber numberWithFloat:(float)mv/1000.0f]];
        break;
      }

      case RECORD_COUNT_MSG:
        mTotalNumRecordsToFetch = (msg[1]&0xff)
        + ((msg[2]&0xff)<<8)
        + ((msg[3]&0xff)<<16)
        + ((msg[4]&0xff)<<24);

        if ([self.delegate respondsToSelector:@selector(BacTrackSkynReceivedRecordCount:)]) {
          [self.delegate BacTrackSkynReceivedRecordCount:mTotalNumRecordsToFetch];
        }

        break;

      case RECORDS_MSG:
        [self parseRecords:msg length:characteristic.value.length];

        NSUInteger processedRecordCount = mWritten + mNonSamplePointRecordCount;
        if ([self.delegate respondsToSelector:@selector(BacTrackSkynProcessedRecordCount:)])
          [self.delegate BacTrackSkynProcessedRecordCount:processedRecordCount];

        if (processedRecordCount >= mTotalNumRecordsToFetch)
        {
          [self handleFinishedRecordBatch];
          return;
        }

        break;

      case CALIBRATION_POINTS_MSG:
      {
        uint8_t calibrationPoint = msg[1]&0xff;
        uint16_t calibrationVersion = (msg[2]&0xff) + ((msg[3]&0xff)<<8);
        uint16_t calibrationLsb = (msg[4]&0xff) + ((msg[5]&0xff)<<8);
        float calibrationConcetration = 0;  // byte 6
        uint32_t calibrationTimestamp = (msg[10]&0xff)
        + ((msg[11]&0xff)<<8)
        + ((msg[12]&0xff)<<16)
        + ((msg[13]&0xff)<<24);

        memcpy(&calibrationConcetration,msg+6,4);

        mCalibrationPoints[SKYN_RESULT_KEY_CALIBRATION_VERSION] = [NSNumber numberWithInt:calibrationVersion];
        mCalibrationPoints[SKYN_RESULT_KEY_TIMESTAMP] = [NSNumber numberWithInt:calibrationTimestamp];
        if (calibrationPoint)
        {
          mCalibrationPoints[SKYN_RESULT_KEY_CALIBRATION_HIGH] = [NSNumber numberWithInt:calibrationLsb];
          mCalibrationPoints[SKYN_RESULT_KEY_CALIBRATION_CONCENTRATION_HIGH] = [NSNumber numberWithFloat:calibrationConcetration];
        }
        else
        {
          mCalibrationPoints[SKYN_RESULT_KEY_CALIBRATION_LOW] = [NSNumber numberWithInt:calibrationLsb];
          mCalibrationPoints[SKYN_RESULT_KEY_CALIBRATION_CONCENTRATION_LOW] = [NSNumber numberWithFloat:calibrationConcetration];
        }

        break;
      }

      case REAL_TIME_RECORD_MSG:
        [self parseRecords:msg length:characteristic.value.length];
        [self requestRecordCount];
        break;
    }
  }
  else if (characteristic == mCharacteristicFirmwareRevision)
  {
    mFirmwareVersion = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];;
    // TODO: I don't know why it's this layer's job to do the "isNewer" comparison, but this might need to happen at some point
    if ([self.delegate respondsToSelector:@selector(BacTrackFirmwareVersion:isNewer:)])
      [self.delegate BacTrackFirmwareVersion:mFirmwareVersion isNewer:NO];
  }
  else if (characteristic == mCharacteristicHardwareRevision)
  {
    // There is currently no API call to retrieve this information
    /*
     NSString *hardwareRevision = [[NSString alloc] initWithData:characteristic.value    encoding:NSUTF8StringEncoding];
     */
  }
  else if (characteristic == mCharacteristicSerialNumber)
  {
    NSString *serialNumber = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    if ([self.delegate respondsToSelector:@selector(BacTrackSerial:)])
      [self.delegate BacTrackSerial:serialNumber];
  }
}

- (NSDictionary*)nextEventOfType:(int)eventCode fromIndex:(int*)idx
{
  int i = *idx;
  NSDictionary *ret;

  for (; i < [mBatchResults count]; i++)
  {
    NSDictionary *d = mBatchResults[i];
    NSString *recordType = d[SKYN_RESULT_KEY_RECORD_TYPE];
    if ([recordType isEqualToString:SKYN_RECORD_TYPE_EVENT])
    {
      if (eventCode == [d[SKYN_RESULT_KEY_EVENT_CODE] intValue])
      {
        ret = d;
        break;
      }
    }
  }

  *idx = i;
  return ret;
}

- (void)fixTimestamps
{
  NSMutableArray *results = [mBatchResults mutableCopy];
  for (int i=0; i < [results count]; i++)
  {
    NSDictionary *powerEvent = [self nextEventOfType:SKYN_EVENT_CODE_POWER_RESTORED fromIndex:&i];
    if (powerEvent)
    {
      int powerEventIdx = i;
      NSDictionary *syncForPower = [self nextEventOfType:SKYN_EVENT_CODE_TIME_SYNC fromIndex:&i];
      if (syncForPower)
      {
        // The very next record MUST be a good timestamp, as specced (p15)
        if (++i < [results count])
        {
          NSDictionary *timestampEvent = results[i];
          NSString *recordType = timestampEvent[SKYN_RESULT_KEY_RECORD_TYPE];
          if ([recordType isEqualToString:SKYN_RECORD_TYPE_TIMINGINFO])
          {
            uint32_t badTimestamp = (uint32_t)[syncForPower[SKYN_RESULT_KEY_TIMESTAMP] integerValue];
            uint32_t goodTimestamp = (uint32_t)[timestampEvent[SKYN_RESULT_KEY_TIMESTAMP] integerValue];
            uint32_t delta = goodTimestamp - badTimestamp;
            for (int j=powerEventIdx+1; j < i; j++)
            {
              NSMutableDictionary *md = [results[j] mutableCopy];
              recordType = md[SKYN_RESULT_KEY_RECORD_TYPE];
              if ([recordType isEqualToString:SKYN_RECORD_TYPE_SENSORCHUNK])
              {
                uint32_t ts = [md[SKYN_RESULT_KEY_TIMESTAMP] unsignedIntValue] + delta;
                md[SKYN_RESULT_KEY_TIMESTAMP] = [NSNumber numberWithUnsignedInt:ts];
                results[j] = md;
              }
            }
          }
          else
          {
            NSLog(@"Failed to recover timestamps: Expected valid TIMINGINFO immediately after TIME_SYNC!");
          }
        }
        else
        {
          // Deals with T1557: device did not appear to send valid data
          NSLog(@"Failed to recover timestamps: TIME_SYNC is last event in batch!");
        }
      }
    }

    // Return an array with only the sample point chunks, and only if the timestamps are more recent than y2k
    // because timestamps that were unrecoverable
    NSMutableArray *filteredResults = [NSMutableArray arrayWithCapacity:4096];
    for (NSDictionary *d in results)
    {
      NSDate *y2k = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
      if ([d[SKYN_RESULT_KEY_RECORD_TYPE] isEqualToString:SKYN_RECORD_TYPE_SENSORCHUNK])
      {
        if ([d[SKYN_RESULT_KEY_TIMESTAMP] unsignedIntValue] >= [y2k timeIntervalSince1970])
          [filteredResults addObject:d];
#ifdef DEBUG
        else
          NSLog(@"Kicked out unrecoverable sensor chunk: %@", d);
#endif
      }
    }

    mBatchResults = filteredResults;
  }
}

- (void)handleFinishedRecordBatch
{
  [self saveSkynChunk];   // Save the last chunk

  [self fixTimestamps];

  if ([self.delegate respondsToSelector:@selector(BacTrackSkynFinishedRecordBatch:)])
    [self.delegate BacTrackSkynFinishedRecordBatch:YES];

  NSDictionary *fullResults = @{SKYN_RESULT_KEY_CALIBRATION: [mCalibrationPoints copy],
                                SKYN_RESULT_KEY_RECORDS: [mBatchResults copy],
                                SKYN_RESULT_KEY_FIRMWARE: [mFirmwareVersion copy]
  };

  if ([self.delegate respondsToSelector:@selector(BacTrackSkynBatchResults:)])
    [self.delegate BacTrackSkynBatchResults:fullResults];

  [self internalDrain];
}

- (void)internalDrain
{
  [mBatchResults removeAllObjects];
}

-(void)handleBacTrackError:(NSError *) error
{
  if ([self.delegate respondsToSelector:@selector(BacTrackError:)]) {
    [self.delegate BacTrackError:error];
  }
}

-(void)startNewSkynChunkAtTimestamp:(uint32_t)ts andSampleRate:(uint32_t)sR
{
  [self saveSkynChunk];

  mChunkTimestamp = ts;
  mChunkSampleRate = sR;
  mChunkSamplePoints = [[NSMutableArray alloc] initWithCapacity:4096];
}

-(void)saveSkynChunk
{
  if ([mChunkSamplePoints count])
  {
    [mBatchResults addObject:@{SKYN_RESULT_KEY_RECORD_TYPE:SKYN_RECORD_TYPE_SENSORCHUNK,
                               SKYN_RESULT_KEY_TIMESTAMP:[NSNumber numberWithUnsignedInt:mChunkTimestamp],
                               SKYN_RESULT_KEY_SAMPLERATE:[NSNumber numberWithUnsignedInt:mChunkSampleRate],
                               SKYN_RESULT_KEY_SAMPLE_POINTS:mChunkSamplePoints
    }];

    mChunkSamplePoints = nil;
  }
}

-(void)startSync
{
  // Tell the peripheral what time it is.
  // TODO: Keep a bitfield of which of these operations have completed and have a BacTrackSkynFinishedSync cb when they are all done, or a failure timeout and error if not...
  [self startNewSkynChunkAtTimestamp:0 andSampleRate:0];
  [self requestTimestamp];
  [self sendCurrentTimestamp];
  [self rewind];
  [self requestRecordCount];
  [self requestBatteryInfo];
  [self requestCalibrationPoints:0];
  [self requestCalibrationPoints:1];
  [self setRealtimeModeEnabled:NO];
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
  if (error) {
    [self handleBacTrackError:error];
  }
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(nullable NSError *)error {
  if (error) {
    [self handleBacTrackError:error];
  }
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error {
  if (error) {
    [self handleBacTrackError:error];
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

  if (![self isConnectedOrConnecting]) {
    return;
  }

  if (service==mServiceSerial) {
    for (CBCharacteristic *characteristic in service.characteristics)
    {
      if([[characteristic.UUID.UUIDString uppercaseString] isEqualToString:[SKYN_SERIAL_GATT_RX_CHAR_UUID uppercaseString]])
        mCharacteristicSerialRx = characteristic;
      else if([[characteristic.UUID.UUIDString uppercaseString] isEqualToString:[SKYN_SERIAL_GATT_TX_CHAR_UUID uppercaseString]])
        mCharacteristicSerialTx = characteristic;
    }
    [mPeripheral setNotifyValue:YES forCharacteristic:mCharacteristicSerialRx];
  }
  else if (service==mServiceVersions) {
    for(CBCharacteristic *characteristic in service.characteristics) {
      if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_SERIAL]]) {
        mCharacteristicSerialNumber = characteristic;
      } else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_HARDWARE_VERSION]]) {
        mCharacteristicHardwareRevision = characteristic;
      } else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION]]) {
        mCharacteristicFirmwareRevision = characteristic;
      }
    }
  }

  [self checkAllServicesDiscovered];

  if (!error) {
    NSLog(@"%@: Characteristics of peripheral found", self.class.description);
  }
}

- (void)checkAllServicesDiscovered
{
  if (mCharacteristicSerialNumber
      && mCharacteristicHardwareRevision
      && mCharacteristicFirmwareRevision
      && mCharacteristicSerialRx
      && mCharacteristicSerialTx)
  {
    // Get the current timestamp. This also will bring up the iOS pairing dialog if not yet bonded
    [self requestTimestamp];
    mFinalizingConnection = YES;
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

  if (![self isConnectedOrConnecting]) {
    return;
  }

  if (!error) {
    NSLog(@"%@: Services of peripheral found", self.class.description);

    // Discover characteristics of found services
    for (CBService * service in mPeripheral.services) {
      // Save service one
      if ([service.UUID isEqual:[CBUUID UUIDWithString:SKYN_SERIAL_GATT_SERVICE_UUID]]) {
        mServiceSerial = service;

        // Discover characteristics
        NSArray * characteristics = @[
          [CBUUID UUIDWithString:SKYN_SERIAL_GATT_RX_CHAR_UUID],
          [CBUUID UUIDWithString:SKYN_SERIAL_GATT_TX_CHAR_UUID],
        ];

        // Find characteristics of service
        [mPeripheral discoverCharacteristics:characteristics forService:service];
      } else if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS]]) {  // device information
        mServiceVersions = service;

        NSArray * characteristics = @[
          [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_SERIAL],
          [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_HARDWARE_VERSION],
          [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_FIRMWARE_VERSION]
        ];

        // Find characteristics of service
        [mPeripheral discoverCharacteristics:characteristics forService:service];
      }
    }
  }
}

- (void)peripheral:(CBPeripheral *)peripheral didModifyServices:(NSArray<CBService *> *)invalidatedServices {
  NSLog(@"%@: Services of peripheral modified: %@", self.class.description, mPeripheral.services);
}


#pragma mark - Device Commands
- (void) requestTimestamp {
  const Byte READ_TIMESTAMP_MSG = 0x00;

  Byte val[1];
  val[0] = READ_TIMESTAMP_MSG;
  NSData *data = [NSData dataWithBytes:&val length:1];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

- (void) sendCurrentTimestamp {
  long timestamp = [[NSDate date] timeIntervalSince1970];
  const Byte SET_TIMESTAMP_MSG = 0x01;

  Byte val[5];
  val[0] = SET_TIMESTAMP_MSG;
  memcpy(&val[1], &timestamp, 4);
  NSData *data = [NSData dataWithBytes:&val length:5];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

- (void) requestBatteryInfo {
  const Byte READ_BATTERY_MILLIVOLTS = 0x02;

  Byte val[1];
  val[0] = READ_BATTERY_MILLIVOLTS;
  NSData *data = [NSData dataWithBytes:&val length:1];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

- (void) requestRecordCount {
  const Byte READ_RECORD_COUNT_MSG = 0x13;

  Byte val[1];
  val[0] = READ_RECORD_COUNT_MSG;
  NSData *data = [NSData dataWithBytes:&val length:1];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

- (void) requestCalibrationPoints:(short) calibrationType{
  const Byte READ_CALIBRATION_POINT_MSG = 0x05;

  Byte val[2];
  val[0] = READ_CALIBRATION_POINT_MSG;
  val[1] = calibrationType;
  NSData *data = [NSData dataWithBytes:&val length:2];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

- (void) setRealtimeModeEnabled:(bool) enabled
{
  const Byte REAL_TIME_RECORD_MSG = 0x17;

  Byte val[2];
  val[0] = REAL_TIME_RECORD_MSG;
  val[1] = enabled;
  NSData *data = [NSData dataWithBytes:&val length:2];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

-(void)getFirmwareVersion
{
  if (mCharacteristicFirmwareRevision)
    [mPeripheral readValueForCharacteristic:mCharacteristicFirmwareRevision];
}

-(void)getBreathalyzerSerialNumber
{
  if (mCharacteristicSerialNumber)
    [mPeripheral readValueForCharacteristic:mCharacteristicSerialNumber];
}

//Turn off real time mode
- (void) internalFetch
{
  mRecordFetchChunkSize = mTotalNumRecordsToFetch-mWritten;

  const Byte FETCH_RECORDS_MSG = 0x14;

  //[Bytes 0:3] : Number of “records” in Skyn’s memory that we’d like sent to the App
  Byte val[5];
  val[0] = FETCH_RECORDS_MSG;
  memcpy(&val[1], &mRecordFetchChunkSize, 4);
  NSData *data = [NSData dataWithBytes:&val length:5];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

- (void) fetchRecords
{
  mWritten = 0;
  mNonSamplePointRecordCount = 0;
  mCounter = 0;
  mCounterWritten = 0;

  [mBatchResults removeAllObjects];

  if (mTotalNumRecordsToFetch == 0)
  {
    NSLog(@"Skyn fetchRecords: No records to fetch. Did you call startSync first?");
    if ([self.delegate respondsToSelector:@selector(BacTrackSkynResultSamplePoint:)])
      [self.delegate BacTrackSkynResultSamplePoint:nil];
    return;
  }

  [self internalFetch];
}

- (void) discardFetchedRecords
{
  const Byte DISCARD_READ_RECORDS = 0x16;

  Byte val[1];
  val[0] = DISCARD_READ_RECORDS;
  NSData *data = [NSData dataWithBytes:&val length:1];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];

  // This is used to confirm that the discard succeeded
  [self rewind];
  [self requestRecordCount];
}

- (void) rewind
{
  const Byte REWIND_RECORDS = 0x15;

  Byte val[1];
  val[0] = REWIND_RECORDS;
  NSData *data = [NSData dataWithBytes:&val length:1];
  [mPeripheral writeValue:data forCharacteristic:mCharacteristicSerialTx type:CBCharacteristicWriteWithResponse];
}

#pragma mark - Testing functions

#ifdef DEBUG

// Convert a CSV back to the a batch results dictionary to fake in readings. This can aid in reproducing crashes.
// Note that it does not currently provide correct units, but it will generate timestamped events
// in the exact order of the original.

// It assumes the default sampling rate of 20

- (NSMutableArray *)csvToDictionary:(NSString*)path
{
  NSMutableArray *ret = [[NSMutableArray alloc] init];
  NSError *err;
  NSString *csvStr = [NSString stringWithContentsOfFile:path encoding:kCFStringEncodingUTF8 error:&err];

  if (!err)
  {

    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];

    NSNumberFormatter *numFormat = [[NSNumberFormatter alloc] init];
    numFormat.numberStyle = NSNumberFormatterDecimalStyle;

    NSArray<NSString*> *csvLines = [csvStr componentsSeparatedByString:@"\n"];
    bool isHeader = YES;    // first line is header
    int i = 0;
    NSInteger lastUnixDate = 0;
    NSMutableArray *curSamplePoints;
    NSNumber *firstTimestampOfChunk;
    for (NSString *csvLine in csvLines)
    {
      if (isHeader)
      {
        isHeader = NO;
        i++;
        continue;
      }
      else if ([csvLine length] == 0) // we are done
      {
        break;
      }

      if (!curSamplePoints)
        curSamplePoints = [[NSMutableArray alloc] init];

      NSArray<NSString*> *fields = [csvLine componentsSeparatedByString:@","];
      NSDate *date = [dateFormatter dateFromString:fields[0]];
      NSInteger unixDate;
      if (date)
      {
        unixDate = [date timeIntervalSince1970];
        if (!firstTimestampOfChunk)
          firstTimestampOfChunk = [NSNumber numberWithInteger:unixDate];
      }
      else
      {
        NSLog(@"Could not parse date on line %d. Aborted.", i);
        return nil;
      }

      // If over ~20 seconds (default sample rate) has elapsed between this line and the last,
      // start a new chunk
      if (lastUnixDate && (unixDate - lastUnixDate) > 21)
      {
        NSDictionary *entry = @{@"record_type": @"sensor_chunk",
                                @"sample_points": curSamplePoints,
                                @"samplerate": @20,
                                @"timestamp": firstTimestampOfChunk
        };
        [ret addObject:entry];
        curSamplePoints = nil;
        firstTimestampOfChunk = nil;
      }

      [curSamplePoints addObject:@[@0, @1, @2]];
      lastUnixDate = unixDate;

      i++;
    } // end for each line

    // Add final chunk
    NSDictionary *entry = @{@"record_type": @"sensor_chunk",
                            @"sample_points": curSamplePoints,
                            @"samplerate": @20,
                            @"timestamp": firstTimestampOfChunk
    };
    [ret addObject:entry];
  }
  else
  {
    NSLog(@"csvToDictionary: %@", err);
  }

  return ret;
}

#endif

@end
