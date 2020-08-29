//
//  BACDeviceMangementProtocol.h
//  BacTrackManagement
//
//  Created by Nick Lane-Smith, Punch Through Design on 3/9/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BacTrackAPIDelegate.h"

@protocol BACDeviceMangementProtocol <NSObject>

@required

-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate AndAPIKey:(NSString*)api_key;

// Connected to breathalyzer. Else timesout after given duration in seconds
-(void)connectBreathalyzer:(Breathalyzer*)breathalyzer withTimeout:(NSTimeInterval)timeout;

// Attempt to connect to the last connected breathalyzer.
// Returns NO if there is no last connected breathalyzer, YES otherwise
-(BOOL)connectToPreviousBreathalyzer;

-(void)connectToNearestBreathalyzerOfType:(BACtrackDeviceType)type;
-(void)connectToNearestBreathalyzer;
-(void)connectToNearestSkyn;

// Forgets the last connected breathalyzer
-(void)forgetLastBreathalyzer;

// Scan for BacTrack breathalyzers
-(void)startScan;
// Scan for Skyn BacTrack devices
-(void)scanForSkyn;

// Stop scanning for BacTrack and Skyn breathalyzers
-(void)stopScan;

// Disconnect from BACTrack or Skyn
-(void)disconnect;

@optional

// Connected to breathalyzer. Else timesout after given duration in seconds
-(void)flashBreathalyzerLEDs:(Breathalyzer*)breathalyzer withTimeout:(NSTimeInterval)timeout;

-(void)fetchSkynRecords;
-(void)skynStartSync;
-(void)discardFetchedSkynRecords;

-(void)writeUnitsToDevice:(BACtrackUnit)units;
-(void)readUnitsFromDevice;

@end
