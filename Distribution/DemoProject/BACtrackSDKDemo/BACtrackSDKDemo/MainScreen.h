//
//  MainScreen.h
//  BACtrackSDKDemo
//
//  Copyright (c) 2018 KHN Solutions LLC. All rights reserved.


#import <UIKit/UIKit.h>
#import "BACtrack.h"

@interface MainScreen : UIViewController <UITableViewDataSource, UITableViewDelegate>
{
    IBOutlet UIButton*                          mShowNearbyDevices;
    IBOutlet UIButton*                          mConnect;
    IBOutlet UIButton*                          mTakeTest;
    IBOutlet UIButton*                          mDisconnect;
    IBOutlet UIButton*                          mRefresh;
    IBOutlet UIButton*                          mClose;
    IBOutlet UIButton*                          mVoltage;
    
    IBOutlet UILabel*                           mReadingLabel;
    IBOutlet UILabel*                           mResultLabel;
    IBOutlet UITableView*                       mTableView;
    
    BOOL                                        mIsConnected;
    int                                         mBatteryLevel;
    
    NSTimer*                                    mStopScanTimer;
}

-(IBAction)showNearbyDevicesTapped:(id)sender;
-(IBAction)connectTapped:(id)sender;
-(IBAction)takeTestTapped:(id)sender;
-(IBAction)disconnectTapped:(id)sender;
-(IBAction)refreshTapped:(id)sender;
-(IBAction)checkVoltageTapped;
-(IBAction)closeTapped:(id)sender;
@end
