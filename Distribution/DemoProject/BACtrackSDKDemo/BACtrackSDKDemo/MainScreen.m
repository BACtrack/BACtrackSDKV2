//
//  MainScreen.m
//  BACtrackSDKDemo
//
//  Copyright (c) 2018 KHN Solutions LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MainScreen.h"
#import "BACtrack.h"
#import "BreathalyzerListCell.h"


@interface MainScreen () <BacTrackAPIDelegate>
{
    BacTrackAPI * mBacTrack;
    NSMutableArray * breathalyzers;
}
@end

@implementation MainScreen

- (void)viewDidLoad
{
    [super viewDidLoad];
    mResultLabel.hidden = YES;
    mReadingLabel.hidden = YES;
    mRefresh.hidden = YES;
    mClose.hidden = YES;
    mBacTrack = [[BacTrackAPI alloc] initWithDelegate:self AndAPIKey:@"insertAPIKeyHere"];
    
    breathalyzers = [NSMutableArray array];
    
    mTableView.dataSource = self;
    mTableView.delegate = self;
    
    // Register the cell reuse identifier for our tableview.
    UINib *cellNib = [UINib nibWithNibName:@"BreathalyzerListCell" bundle:nil];
    [mTableView registerNib:cellNib forCellReuseIdentifier:[BreathalyzerListCell staticReuseIdentifier]];
    
    if([mTableView respondsToSelector:@selector(setSeparatorInset:)])
        [mTableView setSeparatorInset:UIEdgeInsetsZero];
    [self refreshButtonState];
}

-(void)viewDidAppear:(BOOL)animated
{
    [mBacTrack startScan];
    mStopScanTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 target:mBacTrack selector:@selector(stopScan) userInfo:nil repeats:NO];
    [mTableView reloadData];
}

- (void)resetLabels
{
    mReadingLabel.text = @"";
    mResultLabel.text = @"";
    mReadingLabel.hidden = YES;
    mResultLabel.hidden = YES;
}

//API Key valid, you can now connect to a breathlyzer
-(void)BacTrackAPIKeyAuthorized
{
    
}

//API Key declined for some reason
-(void)BacTrackAPIKeyDeclined:(NSString *)errorMessage
{
    UIAlertView * alert =[[UIAlertView alloc ] initWithTitle:@"Invalid Key"
                                                     message:errorMessage
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles: nil];
    [alert addButtonWithTitle:@"OK"];
    [alert show];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)refreshTapped:(id)sender
{
    [breathalyzers removeAllObjects];
    [mTableView reloadData];
    if (mStopScanTimer)
    {
        [mStopScanTimer invalidate];
        mStopScanTimer = nil;
    }
    [mBacTrack stopScan];
    [mBacTrack startScan];
    mStopScanTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 target:mBacTrack selector:@selector(stopScan) userInfo:nil repeats:NO];
}

- (IBAction)checkVoltageTapped
{
    [mBacTrack getBreathalyzerBatteryLevel];
    NSLog(@"Geting battery voltage");
}

-(void)BacTrackSerial:(NSString *)serial_hex
{
    [[[UIAlertView alloc] initWithTitle:@"Serial Number"
                                message:serial_hex
                               delegate:nil
                      cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];

}

-(void)BacTrackUseCount:(NSNumber*)number
{
    NSLog(@"Use count:, %d", number.intValue);
    // uncomment below lines to show use count on countdown
//    [[[UIAlertView alloc] initWithTitle:@"Use Count"
//                                message:[NSString stringWithFormat:@"%d",number.intValue]
//                               delegate:nil
//                      cancelButtonTitle:@"OK"
//                      otherButtonTitles:nil] show];
}
-(void)closeTapped:(id)sender
{
    mTableView.hidden = YES;
    mClose.hidden = YES;
    mRefresh.hidden = YES;
}

- (IBAction)showNearbyDevicesTapped:(id)sender
{
    NSLog(@"Show Nearby Devices Tapped");
    [self.view bringSubviewToFront:mTableView];
    [self.view bringSubviewToFront:mRefresh];
    [self.view bringSubviewToFront:mClose];
    mTableView.hidden = NO;
    mRefresh.hidden = NO;
    mClose.hidden = NO;
}

-(void)connectTapped:(id)sender
{
    NSLog(@"Connect Tapped");
    [mBacTrack connectToNearestBreathalyzer];
}

-(void)takeTestTapped:(id)sender
{
    NSLog(@"Take Test Tapped");
    [mBacTrack startCountdown];
    mResultLabel.hidden = NO;
    mReadingLabel.hidden = NO;
}

-(void)disconnectTapped:(id)sender
{
    NSLog(@"Disconnect Tapped");
    [mBacTrack disconnect];
    [self resetLabels];
    mTableView.hidden = YES;
}

-(void)BacTrackError:(NSError*)error
{
    if(error)
    {
        [self resetLabels];

        NSString* errorDescription = [error localizedDescription];
    
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Sorry!"
                                                     message:errorDescription
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil];
        [av show];
    }
}

// Initialized countdown from number
-(void)BacTrackCountdown:(NSNumber *)seconds executionFailure:(BOOL)failure
{
    if (failure)
    {
        [self BacTrackError:nil];
        return;
    }
    else
    {
        mReadingLabel.text = @"Warming up";
    }
    
    mResultLabel.text = [NSString stringWithFormat: @"%d", seconds.intValue];
}

// Tell the user to start
- (void)BacTrackStart
{
    mReadingLabel.text = @"Blow now!";
    mResultLabel.text = @"";
}

// Tell the user to blow
- (void)BacTrackBlow:(NSNumber*)breathFractionRemaining
{
    mReadingLabel.text = @"Keep blowing!";
    mResultLabel.text = [NSString stringWithFormat:@"%d%%",
                         100 - (int)([breathFractionRemaining floatValue]*100.0)];
}

- (void)BacTrackAnalyzing
{
    mReadingLabel.text = @"Analyzing results";
    mResultLabel.text = @"";
}

-(void)BacTrackResults:(CGFloat)bac
{
    mReadingLabel.text = @"Your Result";
    mResultLabel.text = [NSString stringWithFormat: @"%.2f", bac];
}

-(void)refreshButtonState
{
    if (mIsConnected)
    {
        mConnect.enabled = NO;
        mConnect.alpha = .5;
        mTakeTest.hidden = NO;
        mDisconnect.hidden = NO;
        mRefresh.hidden = NO;
        mClose.hidden = NO;


        mVoltage.hidden = NO;
    }
    else
    {
        mConnect.enabled = YES;
        mConnect.alpha = 1.0;
        mTakeTest.hidden = YES;
        mDisconnect.hidden = YES;
        mRefresh.hidden = YES;
        mClose.hidden = YES;
        mVoltage.hidden = YES;
    }

}
-(void)BacTrackConnected:(BACtrackDeviceType)device
{
    mIsConnected = YES;
    mBatteryLevel = -1;
    [self refreshButtonState];
    NSLog(@"Connected to BACtrack device");
}

-(void)BacTrackDisconnected
{
    mIsConnected = NO;
    mBatteryLevel = -1;
    
    [self resetLabels];
    [self refreshButtonState];
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Disconnected"
                                                 message:@"You are now disconnected from your BACtrack device"
                                                delegate:nil
                                       cancelButtonTitle:@"OK"
                                       otherButtonTitles:nil];
    [av show];
}

-(void)BacTrackConnectTimeout
{
    //Callback for device connection timeout; can use method to reset UI etc
}

-(NSTimeInterval)BacTrackGetTimeout
{
    //Optional, sets a callback timeout timer (in seconds)
    return 10;
}

-(void)BacTrackFoundBreathalyzer:(Breathalyzer*)breathalyzer
{
    //Can use to store/record device id, breathalyzer type, etc.
    //Here I've just listed the breathalyzer type
    NSLog(@"Found breathalyzer: %@", breathalyzer.peripheral.name.description);
    
    NSString *breathalyzerUUID = [breathalyzer.peripheral.identifier UUIDString];
    for (Breathalyzer * breath in breathalyzers)
    {
        NSString *breathUUID = [breath.peripheral.identifier UUIDString];
        
        if ([breathUUID isEqualToString:breathalyzerUUID])
        {
            NSLog(@"%@: Duplicate Breathalyzer UUID found!",self.class.description);
            return;
        }
    }
    [breathalyzers addObject:breathalyzer];
    [mTableView reloadData];
}

- (void) BacTrackBatteryVoltage:(NSNumber *)number
{
    NSLog(@"Battery Voltage: %f", [number floatValue]);
    mResultLabel.hidden = NO;
    mResultLabel.text = [NSString stringWithFormat:@"%.02fv", [number floatValue]];
}

- (void) BacTrackBatteryLevel:(NSNumber *)number
{
    NSLog(@"Battery Level: %d", [number intValue]);
    mReadingLabel.hidden = NO;
    mReadingLabel.text = [NSString stringWithFormat:@"Level: %d", [number intValue]];
    mBatteryLevel = [number intValue];
}


-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BreathalyzerListCell *cell = [tableView dequeueReusableCellWithIdentifier:[BreathalyzerListCell staticReuseIdentifier] forIndexPath:indexPath];
    
    if (cell == nil) {
        cell = [[BreathalyzerListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[BreathalyzerListCell staticReuseIdentifier]];
    }
    
    Breathalyzer * b = [breathalyzers objectAtIndex:indexPath.row];
    if(b)
    {
        cell.breathalyzerTypeLabel.text = b.peripheral.name;
        cell.breathalyzerUUIDLabel.text = b.uuid;
    }
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 1;
}

-(NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return breathalyzers.count;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Breathalyzer * b = [breathalyzers objectAtIndex:indexPath.row];
    if(b)
    {
        [mBacTrack connectBreathalyzer:b withTimeout:10];
        mTableView.hidden = YES;
        mRefresh.hidden = YES;
        mClose.hidden = YES;
    }
}

-(void)dealloc
{
    if (mStopScanTimer)
    {
        [mStopScanTimer invalidate];
        mStopScanTimer = nil;
    }
}

-(void)viewDidUnload
{
    mTableView = nil;
    [super viewDidUnload];
}

@end
