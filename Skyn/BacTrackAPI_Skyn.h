//
//  BacTrackAPI_Skyn.h
//  BACtrack SDK
//
//  Created by Zach Saul on 6/12/18.
//  Copyright © 2018 KHN Solutions. All rights reserved.
//

#import "BacTrackAPIDelegate.h"

@interface BacTrackAPI_Skyn : NSObject
{
    NSMutableArray   * mBatchResults;
    NSMutableDictionary   * mCalibrationPoints;
    NSMutableArray   * mChunkSamplePoints;
}
@property id <BacTrackAPIDelegate> delegate;
@property BACtrackDeviceType type;

- (id) initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral;
- (void) configurePeripheral;
- (void) fetchRecords;
- (void) startSync;
- (void) discardFetchedRecords;
- (void) setRealtimeModeEnabled:(BOOL)isEnabled;   // Turned off automatically on startSync

#ifdef DEBUG
// Exposure for unit tests (TODO: move to a private interface file to reduce clutter)
- (void) fixTimestamps;
- (void) startNewSkynChunkAtTimestamp:(uint32_t)ts andSampleRate:(uint32_t)sR;
- (void) saveSkynChunk;
- (void) handleFinishedRecordBatch;
#endif

@end
