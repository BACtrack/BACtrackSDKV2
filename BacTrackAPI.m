//
//  BacTrackAPI.m
//  BacTrack_Demo
//
//  Created by Kevin Johnson, Punch Through Design on 9/11/12.
//  Copyright (c) 2012 KHN Solutions LLC. All rights reserved.
//

#import <objc/runtime.h>
#import "BacTrackAPI.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "Helper.h"
#import "Globals.h"
#import "Breathalyzer.h"
#import "BacMessage.h"
#import "BacTrackOAD.h"
#import "NSMutableData+AppendHex.h"
#import "DATech/BacTrackAPI_Mobile.h"
#import "BacTrackAPI_Vio.h"
#import "BacTrackAPI_C6_C8.h"
#import "BacTrackAPI_Skyn.h"
#import "BacTrackAPI_MobileV2.h"
#import "Reachability.h"
#import <SystemConfiguration/SystemConfiguration.h>



@interface BacTrackAPI () <CBCentralManagerDelegate, CBPeripheralDelegate> {

    CBService        * serviceHardwareVersion;
    CBCharacteristic * characteristic_model;
    CBCharacteristic * characteristic_serial_number;
    CBCentralManager * cmanager;
    NSTimer          * timer;
    
    CBPeripheral     * lastConnectedBreathalyzer;
    Breathalyzer     * connectingToBreathalyzer;
    
    BOOL               shouldBeScanning;
    BOOL               connected;
    
    // Variables for connecting to the nearest breathalyzer
    BOOL               connectToNearest;
    NSTimer *          nearestBreathalyzerTimer;
    NSMutableArray   * foundBreathalyzers;
    NSArray          * scanUdids;
    
    NSArray *passthroughSelectors;
    NSMutableDictionary *connectedPeripherals;
    NSMutableDictionary *connectedAPIEndpoints;
    
    BacTrackAPI_Skyn    *mSkynApi; //TODO: use currentAPIEndpoint instead of member variable
}

@end

// Note: DeviceInteractionProtocol
//
// We only weakly conform to the DeviceInteractionProtocol.
// We do NOT implment any of the methods, we detect when
// they are passed to us, and pass them to the underlying
// API Object if it implements it.
// Implementing ANY of the methods here will case them not to be forwarded.

// This hides warnings about not comformting to protocol
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
@implementation BacTrackAPI


#pragma mark -
#pragma mark Message Forwarding
/****************************************************************************/
/*								Message Forwarding                          */
/****************************************************************************/

-(id)currentAPIEndpoint
{
    id <BACDeviceInteractionProtocol> api;
    api = [connectedAPIEndpoints objectForKey:lastConnectedBreathalyzer.identifier];
    return api;
}


-(void)setDelegate:(id<BacTrackAPIDelegate>)delegate
{
    _delegate = delegate;
    if ([connectedAPIEndpoints count] > 0) {
        id<BACDeviceInteractionProtocol> api = [self currentAPIEndpoint];
        [api setDelegate:delegate];
    }
}

- (void)loadProtocolSelectors
{
    Protocol *p = objc_getProtocol("BACDeviceInteractionProtocol");
    
    NSMutableArray *selectors = [NSMutableArray arrayWithCapacity:30];
    unsigned int outCount;
    struct objc_method_description * methods = NULL;
    
    //getrequired for now.
    methods = protocol_copyMethodDescriptionList(p, YES, YES, &outCount);
    
    for (unsigned int i = 0; i < outCount; ++i) {
        SEL selector = methods[i].name;
        NSString *selString = NSStringFromSelector(selector);
        [selectors addObject:selString];
    }
    //we HAVE to free methods or leak.
    if (methods) free(methods);
    methods = NULL;
    passthroughSelectors = selectors;
}


- (void)forwardInvocation: (NSInvocation*)invocation
{
    id<BACDeviceInteractionProtocol> api = [self currentAPIEndpoint];
    return [invocation invokeWithTarget:api];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    //See if method if found in our protocol
    if([passthroughSelectors containsObject:NSStringFromSelector(sel)]) {
        id<BACDeviceInteractionProtocol> api = [self currentAPIEndpoint];

        //check API endpoint responds to selector
        if ([api respondsToSelector:sel]) {
            NSMethodSignature* sig = [[api class]
                                      instanceMethodSignatureForSelector:sel];
            return sig;
        }
    }

    return [super methodSignatureForSelector: sel];
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
        shouldBeScanning = NO;
        connected = NO;
        connectToNearest = NO;
       
        [self loadProtocolSelectors];
        connectedPeripherals = [[NSMutableDictionary alloc] initWithCapacity:1];
        connectedAPIEndpoints = [[NSMutableDictionary alloc] initWithCapacity:1];
        cmanager = [[CBCentralManager alloc] initWithDelegate:self
                                                           queue:nil
                                                         options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:CBCentralManagerOptionShowPowerAlertKey]];
        
        NSLog(@"%@: CBCentralManager initialized", self.class.description);
    }

    return self;
}


-(id)initWithDelegate:(id<BacTrackAPIDelegate>)delegate AndAPIKey:(NSString*)api_key
{
    
//#ifdef SKIP_API_KEY_CHECK
//    NSLog(@"Skipped API Key Check");
//    self.delegate = delegate;
//    return [self init];
//#else
    NSLog(@"Performing API Key Check");
    [self updateAPIapprovalStatusWithKey: api_key];
    self.delegate = delegate;
    return [self init];
//#endif
    
}

- (CBCentralManagerState)getState
{
    return cmanager.state;
}

-(void)startScan
{
    [foundBreathalyzers removeAllObjects];
    shouldBeScanning = YES;
    connectToNearest = NO;
    
    if(scanUdids == nil)
        scanUdids = @[
                      [CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_ONE],
                      [CBUUID UUIDWithString:VIO_BACTRACK_SERVICE_ONE],
                      [CBUUID UUIDWithString:C6_ADVERTISED_SERVICE_UUID],
                      [CBUUID UUIDWithString:MOBILEV2_ADVERTISED_SERVICE_UUID]
                      ];

    // Start scanning for BACTrack
    [cmanager scanForPeripheralsWithServices:scanUdids options:0];
}

-(void)scanForSkyn
{
    [foundBreathalyzers removeAllObjects];
    shouldBeScanning = YES;
    connectToNearest = NO;
    
    if(scanUdids == nil)
        scanUdids = @[
                      [CBUUID UUIDWithString:SKYN_ADVERTISED_SERVICE_UUID],
                      ];

    // Start scanning for BACTrack
    [cmanager scanForPeripheralsWithServices:scanUdids options:0];
}

-(void)stopScan
{
    shouldBeScanning = NO;
    connectToNearest = NO;
    
    [cmanager stopScan];
}

-(void)connectBreathalyzer:(Breathalyzer*)breathalyzer withTimeout:(NSTimeInterval)timeout
{
    NSLog(@"%@: Attempting to connect to a BACTrack peripheral...", self.class.description);

#ifdef SKIP_API_KEY_CHECK
    connectingToBreathalyzer = breathalyzer;
    [cmanager connectPeripheral:breathalyzer.peripheral options:nil];
    // Set the timeout
    timer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(connectTimeout) userInfo:nil repeats:NO];
#else
    if ([[[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys] containsObject:@"BACTRACK_API_USE_APPROVED"])
    {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"BACTRACK_API_USE_APPROVED"])
        {
            // Success Case.
            NSLog(@"API Key Verification Success");
            if ([self.delegate respondsToSelector:@selector(BacTrackAPIKeyAuthorized)])
                [self.delegate BacTrackAPIKeyAuthorized];
        }
        else
        {
            // Fail Case.
            NSLog(@"API Key Verification fail");
            [self.delegate BacTrackAPIKeyDeclined:@"Verification of the included BACtrack API Key has failed."];
            return;
        }
    }
    else
    {
        // Success Case.
        // User has never connected to the Internet and performed initial API key verification.
        NSLog(@"User has not completed initial verification");
        NSLog(@"API Key Verification Success");
        if ([self.delegate respondsToSelector:@selector(BacTrackAPIKeyAuthorized)])
            [self.delegate BacTrackAPIKeyAuthorized];
    }
    
    connectingToBreathalyzer = breathalyzer;
    [cmanager connectPeripheral:breathalyzer.peripheral options:nil];
    // Set the timeout
    timer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(connectTimeout) userInfo:nil repeats:NO];
#endif

}

-(BOOL)connectToPreviousBreathalyzer
{
    if (lastConnectedBreathalyzer) {
        [cmanager connectPeripheral:lastConnectedBreathalyzer options:nil];
        return YES;
    }
    else {
        return NO;
    }
}

- (void) connectToNearestBreathalyzerOfType:(BACtrackDeviceType) type
{
    switch (type) {
        case BACtrackDeviceType_Mobile:
            scanUdids = @[[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_ONE]];
            break;
            
        case BACtrackDeviceType_Vio:
            scanUdids = @[[CBUUID UUIDWithString:VIO_BACTRACK_SERVICE_ONE]];
            break;
            
        case BACtrackDeviceType_C6:
        case BACtrackDeviceType_C8:
            scanUdids = @[[CBUUID UUIDWithString:C6_ADVERTISED_SERVICE_UUID]];
            break;

        case BACtrackDeviceType_Skyn:
            scanUdids = @[[CBUUID UUIDWithString:SKYN_ADVERTISED_SERVICE_UUID]];
            break;

        default:
            return;
    }
    
    [self connectToNearestBreathalyzer];
    
}

-(void)performAPIKeyCheck
{
#ifndef SKIP_API_KEY_CHECK
    if ([[[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys] containsObject:@"BACTRACK_API_USE_APPROVED"])
    {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"BACTRACK_API_USE_APPROVED"])
        {
            // Success Case.
            NSLog(@"API Key Verification Success");
            if ([self.delegate respondsToSelector:@selector(BacTrackAPIKeyAuthorized)])
                [self.delegate BacTrackAPIKeyAuthorized];
        }
        else
        {
            // Fail Case.
            NSLog(@"API Key Verification Fail");
            [self.delegate BacTrackAPIKeyDeclined:@"Verification of the included BACtrack API Key has failed."];
            scanUdids = nil;
            return;
        }
    }
    else
    {
        NSLog(@"API Key Verification Success");
        if ([self.delegate respondsToSelector:@selector(BacTrackAPIKeyAuthorized)])
            [self.delegate BacTrackAPIKeyAuthorized];
    }
#endif
}

-(void)connectToNearestBreathalyzer
{
    NSLog(@"Connecting to nearest breathalyzer");
    [self performAPIKeyCheck];
    [self doConnectToNearestBreathalyzerWithSkynMode:NO];
}

-(void)connectToNearestSkyn
{
    NSLog(@"Connecting to nearest Skyn");
    [self performAPIKeyCheck];
    [self doConnectToNearestBreathalyzerWithSkynMode:YES];
}

-(void)forgetLastBreathalyzer
{
    if (lastConnectedBreathalyzer) {
        [cmanager cancelPeripheralConnection:lastConnectedBreathalyzer];
        lastConnectedBreathalyzer = nil;
    }
}

- (BOOL)peripheralAreConnected
{
    BOOL ret = NO;
    for (NSString *key in connectedPeripherals) {
        CBPeripheral *peripheral = (CBPeripheral *)[connectedPeripherals objectForKey:key];
        ret |= (peripheral.state == CBPeripheralStateConnected );
    }
    return ret;
}

-(void)allPeripheralsDisconnected
{
    //XXX cleanup hardware/connected/etc.
    [connectedPeripherals removeAllObjects];
}

/// Cleans all characteristics and services
-(void)peripheralDisconnected:(CBPeripheral*)peripheral
{
    connected = NO;
    serviceHardwareVersion = nil;
    
    [[self currentAPIEndpoint] peripheralDisconnected:peripheral];
    
    if ([self.delegate respondsToSelector:@selector(BacTrackDisconnected)]) {
        [self.delegate BacTrackDisconnected];
    }

    [connectedPeripherals removeObjectForKey:peripheral.identifier];
}

-(void)disconnect
{
    [connectedAPIEndpoints removeAllObjects];
    
    NSMutableArray *deleteKeys = [NSMutableArray new];
    
    for (NSString *key in connectedPeripherals) {
        [cmanager cancelPeripheralConnection: [connectedPeripherals objectForKey:key]];
        [deleteKeys addObject:key];
    }
    
    for (NSString *key in deleteKeys)
    {
        [connectedPeripherals removeObjectForKey:key];
    }
    
    if (connectingToBreathalyzer && connectingToBreathalyzer.peripheral) {
        [cmanager cancelPeripheralConnection:connectingToBreathalyzer.peripheral];
    }
    for (Breathalyzer * breathalyzer in foundBreathalyzers) {
        if (breathalyzer.peripheral) {
            [cmanager cancelPeripheralConnection:breathalyzer.peripheral];
        }
    }
}

#pragma mark -
#pragma mark Private Methods
/****************************************************************************/
/*								Private Methods                             */
/****************************************************************************/



-(void)updateAPIapprovalStatusWithKey: (NSString*)api_key
{
    // Check for Internet connection.
    NSNumber *result = [[NSUserDefaults standardUserDefaults] objectForKey:@"BACTRACK_API_USE_APPROVED"];
    if (!result) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey: @"BACTRACK_API_USE_APPROVED"];
    }
    if ([[Reachability reachabilityForInternetConnection]currentReachabilityStatus]==NotReachable)
    {
        return;
    }
    
    NSLog(@"Sending API Key to Server for Verification");
    NSString *URLString = [NSString stringWithFormat:@"https://developer.bactrack.com/verify?api_token=%@", api_key];
    NSURL *URL = [NSURL URLWithString:URLString];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    request.HTTPMethod = @"GET";
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 200)
        {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey: @"BACTRACK_API_USE_APPROVED"];
        }
        else if (httpResponse.statusCode == 401)
        {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey: @"BACTRACK_API_USE_APPROVED"];
        }
        
    }] resume];
    
}


-(void)doConnectToNearestBreathalyzerWithSkynMode:(BOOL)isSkynMode
{
    NSLog(@"cmanger.state: %ld", (long)cmanager.state);
    if(cmanager.state == CBCentralManagerStatePoweredOn)
    {
        [nearestBreathalyzerTimer invalidate];
        nearestBreathalyzerTimer = nil;
        
        [self stopScan];
        if (isSkynMode)
            [self scanForSkyn];
        else
            [self startScan];
        connectToNearest = YES;
    }
    else
    {
        if (isSkynMode)
            [self performSelector:@selector(connectToNearestSkyn) withObject:nil afterDelay:1.0];
        else
            [self performSelector:@selector(connectToNearestBreathalyzer) withObject:nil afterDelay:1.0];
    }
}

-(NSArray*)uuidArrayFromServices:(NSArray*)cbservices{
    NSMutableArray* array = [[NSMutableArray alloc] init];
    for(CBService* service in cbservices){
        [array addObject:[service UUID]];
    }
    return [array copy];
}

- (void)getDiscoveredBreathalyzerType:(Breathalyzer*)breathalyzer withServices:(NSArray*)services{
    if(services){
        if([services count] >=2
           && [[services objectAtIndex:1] isEqual:[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_TWO]]){
            breathalyzer.type = BACtrackDeviceType_Mobile;
        }else if([services count] >=1
                 && [[services objectAtIndex:0] isEqual:[CBUUID UUIDWithString:MOBILEV2_ADVERTISED_SERVICE_UUID]]){
            breathalyzer.type = BACtrackDeviceType_MobileV2;
        }else if([services count] >=1
                 && [[services objectAtIndex:0] isEqual:[CBUUID UUIDWithString:VIO_BACTRACK_SERVICE_ONE]]){
            breathalyzer.type = BACtrackDeviceType_Vio;
        }else if ([services count] >=1
                 && [[services objectAtIndex:0] isEqual:[CBUUID UUIDWithString:C6_ADVERTISED_SERVICE_UUID]]){
            breathalyzer.type = BACtrackDeviceType_C6;  // Tentative-- it might still be a C8
        }
        else if ([services count] >=1
              && [[services objectAtIndex:0] isEqual:[CBUUID UUIDWithString:SKYN_ADVERTISED_SERVICE_UUID]]) {
            breathalyzer.type = BACtrackDeviceType_Skyn;
        }
        else{
            breathalyzer.type = BACtrackDeviceType_Unknown;
        }
    }else{
        breathalyzer.type = BACtrackDeviceType_Unknown;
    }
}

- (void)setupDATechAPI:(CBPeripheral *)peripheral
{
    NSLog(@"%s -- should only see thus once", __PRETTY_FUNCTION__);
    BacTrackAPI_Mobile *api = [[BacTrackAPI_Mobile alloc] initWithDelegate:self.delegate peripheral:peripheral];
    [connectedAPIEndpoints setObject:api forKey:peripheral.identifier];

    [api configurePeripheral];
}

- (void)setupMobileV2API:(CBPeripheral *)peripheral
{
    BacTrackAPI_MobileV2 *api = [[BacTrackAPI_MobileV2 alloc] initWithDelegate:self.delegate peripheral:peripheral];
    [connectedAPIEndpoints setObject:api forKey:peripheral.identifier];
    [api configurePeripheral];
}

- (void)setupKotexAPI:(CBPeripheral *)peripheral
{
    BacTrackAPI_Vio *api = [[BacTrackAPI_Vio alloc] initWithDelegate:self.delegate peripheral:peripheral];
    [connectedAPIEndpoints setObject:api forKey:peripheral.identifier];
    [api configurePeripheral];
}

- (void)setupC6:(CBPeripheral *)peripheral
{
    BacTrackAPI_C6 *api = [[BacTrackAPI_C6 alloc] initWithDelegate:self.delegate peripheral:peripheral];
    api.type = BACtrackDeviceType_C6;
    [connectedAPIEndpoints setObject:api forKey:peripheral.identifier];
    [api configurePeripheral];
    // Default when first detecting a C6/C8 is C6, so we don't need to set it here (unlike setupC8)
}

- (void)setupC8:(CBPeripheral *)peripheral
{
    BacTrackAPI_C6 *api = [[BacTrackAPI_C6 alloc] initWithDelegate:self.delegate peripheral:peripheral];
    api.type = BACtrackDeviceType_C8;
    [connectedAPIEndpoints setObject:api forKey:peripheral.identifier];
    [api configurePeripheral];
    for (Breathalyzer *b in foundBreathalyzers) {
        if (b.peripheral == peripheral) {
            b.type = BACtrackDeviceType_C8;
        }
    }
}

- (void)setupSkyn:(CBPeripheral *)peripheral
{
    mSkynApi = [[BacTrackAPI_Skyn alloc] initWithDelegate:self.delegate peripheral:peripheral];
    [connectedAPIEndpoints setObject:mSkynApi forKey:peripheral.identifier];

    [mSkynApi configurePeripheral];
    mSkynApi.type = BACtrackDeviceType_Skyn;
    for (Breathalyzer *b in foundBreathalyzers) {
        if (b.peripheral == peripheral) {
            b.type = BACtrackDeviceType_Skyn;
        }
    }
}

- (void) skynStartSync
{
    [mSkynApi startSync];
}

- (void) fetchSkynRecords
{
    [mSkynApi fetchRecords];
}

- (void) discardFetchedSkynRecords
{
    [mSkynApi discardFetchedRecords];
}

- (void) writeUnitsToDevice:(BACtrackUnit)units
{
    id<BACDeviceMangementProtocol> api = [self currentAPIEndpoint];
    if ([api respondsToSelector:@selector(writeUnitsToDevice:)])
    {
        [api writeUnitsToDevice:units];
    }
}

-(void)connectTimeout
{
    NSLog(@"%@: Connection attempt timed out", self.class.description);
    
    connectToNearest = NO;
    // Stop scanning
    [cmanager stopScan];
    
    // Stop trying to connect if connecting to a peripheral
    //XXX this will just blow away everything, better idea?
    [self disconnect];
    
    if ([self.delegate respondsToSelector:@selector(BacTrackConnectTimeout)])
        [self.delegate BacTrackConnectTimeout];
}

#pragma mark -
#pragma mark CBCentralManagerDelegate
/****************************************************************************/
/*			     CBCentralManagerDelegate protocol methods beneeth here     */
/****************************************************************************/

- (void) centralManagerDidUpdateState:(CBCentralManager *)central
{
    if([self.delegate respondsToSelector:@selector(BacTrackBluetoothStateChanged:)])
        [self.delegate BacTrackBluetoothStateChanged:central.state];
    switch ([central state]) {
        case CBCentralManagerStatePoweredOn:
            NSLog(@"%@: Bluetooth is powered on", self.class.description);
            if (shouldBeScanning) {
                BOOL connect = connectToNearest;
                [self startScan];
                connectToNearest  = connect;
            }
            return;
            break;
		case CBCentralManagerStatePoweredOff:
		{
            NSLog(@"%@: Bluetooth is powered off", self.class.description);
            // Bluetooth is not on
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
            [errorDetail setValue:@"Turn on bluetooth from the General settings" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"Bluetooth is not on" code:100 userInfo:errorDetail];
            if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
                [self.delegate BacTrackError:error];
            break;
		}
		case CBCentralManagerStateUnauthorized:
		{
            NSLog(@"%@: Bluetooth unauthorized", self.class.description);

			/* Tell user the app is not allowed. */
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
            [errorDetail setValue:@"The app is not allowed to use bluetooth" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"Bluetooth Error" code:100 userInfo:errorDetail];
            if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
                [self.delegate BacTrackError:error];
            
			break;
		}

            
		case CBCentralManagerStateUnknown:
		{
            NSLog(@"%@: Bluetooth state unknown", self.class.description);

			/* Bad news, let's wait for another event. */
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
            [errorDetail setValue:@"Bluetooth is in a unknown state" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"Bluetooth Unknown" code:100 userInfo:errorDetail];
            if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
                [self.delegate BacTrackError:error];
            
			break;
		}
            
		case CBCentralManagerStateResetting:
		{
            NSLog(@"%@: Bluetooth state resetting", self.class.description);

            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
            [errorDetail setValue:@"Bluetooth is resetting..." forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"Bluetooth Resetting" code:100 userInfo:errorDetail];
            if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
                [self.delegate BacTrackError:error];
            
			break;
		}
        case CBCentralManagerStateUnsupported:
        {
            NSLog(@"%@: Bluetooth state unsupported", self.class.description);

            // Unsupported
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
            [errorDetail setValue:@"Bluetooth is unsupported" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"Bluetooth Unsupported" code:100 userInfo:errorDetail];
            if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
                [self.delegate BacTrackError:error];
            
            break;
        }
        default:
        {
            NSLog(@"%@: Invalid Bluetooth Configuration", self.class.description);
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
            [errorDetail setValue:@"Unknown bluetooth state" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"Bluetooth Error" code:100 userInfo:errorDetail];
            if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
                [self.delegate BacTrackError:error];
            
        }
            
	}
    

    BOOL allConnected = [self peripheralAreConnected];

    
    // Check to make sure peripheral is still connected
    if (!allConnected) {
        NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
        [errorDetail setValue:@"You are not connected to BACTrack" forKey:NSLocalizedDescriptionKey];
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:100 userInfo:errorDetail];
        if ([self.delegate respondsToSelector:@selector(BacTrackError:)])
            [self.delegate BacTrackError:error];

    }
}

-(void)centralManager:(CBCentralManager *)central didRetrieveConnectedPeripherals:(NSArray *)peripherals
{
    // Do nothing until breathalyzer is identified
    // See centralManager:didDiscoverPeripheral:...
}

-(void)returnNearestBreathalyzer
{
    [nearestBreathalyzerTimer invalidate];
    nearestBreathalyzerTimer = nil;
    connectToNearest = NO;
    
    Breathalyzer * breathalyzer;
    for (Breathalyzer * b in foundBreathalyzers) {
        if (!breathalyzer || b.rssi.integerValue > breathalyzer.rssi.integerValue) {
            breathalyzer = b;
        }
    }
    
    if (breathalyzer) {
        if ([self.delegate respondsToSelector:@selector(BacTrackFoundBreathalyzer:)])
            [self.delegate BacTrackFoundBreathalyzer:breathalyzer];
    }
    [self stopScan];
    
    scanUdids = nil;

    connectingToBreathalyzer = breathalyzer;
    
    //consider a delay
    NSLog(@"connecting");
    [cmanager connectPeripheral:breathalyzer.peripheral options:nil];
    
    NSTimeInterval timeout = 12; // Default timeout to 12 seconds
    if ([self.delegate respondsToSelector:@selector(BacTrackGetTimeout)]) {
        timeout = [self.delegate BacTrackGetTimeout];
    }
    
    // Set timeout
    timer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(connectTimeout) userInfo:nil repeats:NO];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    
    NSLog(@"%@: Discovered BacTrack Breathalyzer: %@", self.class.description, peripheral.name);
    
    Breathalyzer * breathalyzer = [Breathalyzer new];
    breathalyzer.peripheral = peripheral;
    breathalyzer.rssi = RSSI;
    breathalyzer.uuid = peripheral.identifier.UUIDString;
    
    [self getDiscoveredBreathalyzerType:breathalyzer withServices:[advertisementData objectForKey:@"kCBAdvDataServiceUUIDs"]];
    
    if(breathalyzer.type != BACtrackDeviceType_Unknown)
    {
        if (!foundBreathalyzers)
            foundBreathalyzers = [NSMutableArray array];
        [foundBreathalyzers addObject:breathalyzer];

        if (connectToNearest) {
            if (!nearestBreathalyzerTimer) {
                nearestBreathalyzerTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(returnNearestBreathalyzer) userInfo:nil repeats:NO];
            }
        }
        else {
            if ([self.delegate respondsToSelector:@selector(BacTrackFoundBreathalyzer:)])
                [self.delegate BacTrackFoundBreathalyzer:breathalyzer];
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    // Stop timeout timer
    [timer invalidate];
    timer = nil;
    
    NSLog(@"%@: Successfully connected to peripheral: %@", self.class.description, peripheral.identifier.UUIDString);
    
    connectingToBreathalyzer = nil;
    
    if ([self.delegate respondsToSelector:@selector(BacTrackDidConnect)]) {
        [self.delegate BacTrackDidConnect];
    }
    
    Breathalyzer * breathalyzer = [Breathalyzer new];
    breathalyzer.peripheral = peripheral;
    [connectedPeripherals setObject:peripheral forKey:peripheral.identifier];
    lastConnectedBreathalyzer = peripheral;
    
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}


-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"%@: Successfully disconnected from peripheral with UUID: %@", self.class.description, peripheral.identifier.UUIDString);
    
    [self peripheralDisconnected:peripheral];
}

-(void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    connectingToBreathalyzer = nil;
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

- (BACtrackDeviceType)deviceTypeForC6C8Serial:(NSString*)serial
{
    if (!serial || [serial length] == 0)
        return BACtrackDeviceType_Unknown;
    
    char firstSerialChar = [serial characterAtIndex:0];
    if (firstSerialChar == '0')
        return BACtrackDeviceType_C6;
    else if (firstSerialChar == '1')
        return BACtrackDeviceType_C8;
    
    return BACtrackDeviceType_Unknown;
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (peripheral && characteristic)
    {
        if (!error) {
            if ([characteristic isEqual:characteristic_serial_number]) {
                if([peripheral.name isEqualToString: @"Skyn"])
                {
                    [self setupSkyn:peripheral];
                }
                
                for (Breathalyzer *b in foundBreathalyzers) {
                    if (b.peripheral == peripheral) {
                        b.serial = [[NSString alloc] initWithData:characteristic.value encoding:NSASCIIStringEncoding];
                    }
                    if (b.type == BACtrackDeviceType_C6) {
                        // Distinguish between C6/C8 via serial number (per flowchart)
                        b.type = [self deviceTypeForC6C8Serial:b.serial];
                        switch (b.type) {
                            case BACtrackDeviceType_C6:
                                [self setupC6:peripheral];
                                break;
                            case BACtrackDeviceType_C8:
                                [self setupC8:peripheral];
                                break;
                            default:
                                NSLog(@"Breathalyzer connection failed: Device identified as a C6 or C8 but has an invalid serial number (must begin with 0 or 1): %@", b.serial);
                                if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
                                    [self.delegate BacTrackConnectionError];
                                [self disconnect];
                        }
                    }
                }

            }
        }
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
        for (CBService *service in peripheral.services) {
            NSLog(@"Discovered service: %@", service.UUID);
            if ([service.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_SERVICE_VERSIONS]]) {
                serviceHardwareVersion = service;

                NSArray * characteristics = [NSArray arrayWithObjects:
                                             [CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_MODEL],
                                             [CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_SERIAL],
                                             nil];

                // Find characteristics of service
                [peripheral discoverCharacteristics:characteristics forService:service];
            }
        }
    }
    else {
        NSLog(@"%@: Service discovery was unsuccessful", self.class.description);
        
        if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
            [self.delegate BacTrackConnectionError];
        
        // Disconnect from peripheral
        [self disconnect];
    }
    
    Breathalyzer *b;
    for (b in foundBreathalyzers) {
        if (b.peripheral == peripheral)
            break;
    }
    if (!b)
    {
        if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
            [self.delegate BacTrackConnectionError];
    }

    bool hasMobileV1ServiceOne = false;
    bool hasMobileV1ServiceTwo = false;
    bool hasRefreshService = false;
    bool hasSkynService = false;
    
    for (CBService *service in peripheral.services) {
        if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_ONE]])
            hasMobileV1ServiceOne = true;
        else if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILE__BACTRACK_SERVICE_TWO]])
            hasMobileV1ServiceTwo = true;
        else if ([service.UUID isEqual:[CBUUID UUIDWithString:MOBILEV2_BREATH_SERVICE_UUID]])
            hasRefreshService = true;
        else if ([service.UUID isEqual:[CBUUID UUIDWithString:SKYN_ADVERTISED_SERVICE_UUID]])
            hasSkynService = true;
    }
    
    if (hasMobileV1ServiceOne && hasMobileV1ServiceTwo && [b.peripheral.name isEqualToString:@"Smart Breathalyzer"]) {
        [self setupDATechAPI:peripheral];
    }
    else if (hasRefreshService) {
        [self setupMobileV2API:peripheral];
    }
    else if (hasSkynService) {
        // Don't do anything here; just don't disconnect!
    }
    else if (b.type == BACtrackDeviceType_C6) {
        // Hold off; wait for serial number
    }
    else {
        NSLog(@"Breathalyzer connection failed: Device unknown: %@", peripheral.description);
        if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
            [self.delegate BacTrackConnectionError];
        [self disconnect];
    }
}

/*
 *  @method didDiscoverCharacteristicsForService
 *
 *  @param peripheral Peripheral that got updated
 *  @param service Service that characteristics where found on
 *  @error error Error message if something went wrong
 *
 *  @discussion didDiscoverCharacteristicsForService is called when CoreBluetooth has discovered
 *  characteristics on a service, on a peripheral after the discoverCharacteristics routine has been called on the service
 *
 */

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {

    if (!error) {
        NSLog(@"%@: Characteristics of peripheral found", self.class.description);

        if ([service isEqual:serviceHardwareVersion]) {
            for (CBCharacteristic * characteristic in service.characteristics) {
                if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_BACTRACK_CHARACTERISTIC_MODEL]]) {
                    characteristic_model = characteristic;
                    [peripheral readValueForCharacteristic:characteristic_model];
                } else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:GLOBAL_CHARACTERISTIC_SERIAL]]) {
                    characteristic_serial_number = characteristic;
                    [peripheral readValueForCharacteristic:characteristic_serial_number];
                }
            }
        } else {
            NSLog(@"%@: Characteristics discovery was unsuccessful", self.class.description);
            
            if ([self.delegate respondsToSelector:@selector(BacTrackConnectionError)])
                [self.delegate BacTrackConnectionError];
            
            // Disconnect from peripheral
            [self disconnect];
        }
    }
}

@end
#pragma clang diagnostic pop
