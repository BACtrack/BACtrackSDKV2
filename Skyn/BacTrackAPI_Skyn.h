//
//  BacTrackAPI_Skyn.h
//  BACtrack SDK
//
//  Created by Zach Saul on 6/12/18.
//  Copyright © 2018 KHN Solutions. All rights reserved.
//

#import "BacTrackAPIDelegate.h"

@interface BacTrackAPI_Skyn : NSObject

@property id <BacTrackAPIDelegate> delegate;
@property BACtrackDeviceType type;

- (id) initWithDelegate:(id<BacTrackAPIDelegate>)delegate peripheral:(CBPeripheral *)peripheral;
- (void) configurePeripheral;
- (void) fetchRecords;
- (void) startSync;
- (void) discardFetchedRecords;
- (void) setRealTimeModeEnabled:(bool)enabled;

@end
