//
//  BACtrackBLEManager.h
//  BACtrack
//
//  Created by Zach Saul on 6/12/18.
//  Copyright © 2018 KHN Solutions. All rights reserved.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@class BacTrackAPI;

@interface BACtrackReactBLEManager : RCTEventEmitter <RCTBridgeModule>
{
    BacTrackAPI *mBacTrackApi;
}
@end
