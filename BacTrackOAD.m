//
//  BacTrackOAD.m
//  BacTrackManagement
//
//  Created by Kevin Johnson, Punch Through Design on 3/6/13.
//  Copyright (c) 2013 Punch Through Design. All rights reserved.
//

#import "BacTrackOAD.h"
#import "BLEUtility.h"

#define HI_UINT16(a) (((a) >> 8) & 0xff)
#define LO_UINT16(a) ((a) & 0xff)

@interface BacTrackOAD () {
    NSString * pathA;
    NSString * pathB;
    bool readyToInitiateImageTransfer;
}

@property (strong,nonatomic) NSData *imageFile;
@property (strong,nonatomic) BLEDevice *d;

@property int nBlocks;
@property int nBytes;
@property int iBlocks;
@property int iBytes;
@property BOOL canceled;
@property BOOL inProgramming;
@property (nonatomic,strong) NSTimer *imageDetectTimer;
@property uint16_t imgVersion;

@end

@implementation BacTrackOAD

-(void)firmwareReadyToUpdate
{
    if ([self validateImage:pathA]) {
        // Image A is valid and uploading
    }
    else if ([self validateImage:pathB]) {
        // Image B is valid and uploading
    }
    else {
        // Both images are invalid!
        
        if ([self.delegate respondsToSelector:@selector(BacTrackOADInvalidImage)]) {
            [self.delegate BacTrackOADInvalidImage];
        }
    }
}

-(void)updateFirmwareForDevice:(BLEDevice *)dev withImageAPath:(NSString*)imageApath andImageBPath:(NSString*)imageBpath
{
    pathA = imageApath;
    pathB = imageBpath;
    
    self.d = dev;
    //self.d.p.delegate = self;
    self.canceled = FALSE;
    self.inProgramming = FALSE;
    readyToInitiateImageTransfer = FALSE;
    [self makeConfigurationForProfile];
    [self configureProfile];
}

-(void)cancelFirmware
{
    self.canceled = YES;
    self.inProgramming = NO;
}


-(void) makeConfigurationForProfile {
    if (!self.d.setupData) self.d.setupData = [[NSMutableDictionary alloc] init];
    // Append the UUID to make it easy for app
    [self.d.setupData setValue:@"0xF000FFC0-0451-4000-B000-000000000000" forKey:@"OAD Service UUID"];
    [self.d.setupData setValue:@"0xF000FFC1-0451-4000-B000-000000000000" forKey:@"OAD Image Notify UUID"];
    [self.d.setupData setValue:@"0xF000FFC2-0451-4000-B000-000000000000" forKey:@"OAD Image Block Request UUID"];
    NSLog(@"makeConfigurationForProfile: %@",self.d.setupData);
}

-(void) configureProfile {
    NSLog(@"Configurating OAD Profile");
    CBUUID *sUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Service UUID"]];
    CBUUID *cUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Notify UUID"]];
    [BLEUtility setNotificationForCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID enable:YES];
    unsigned char data = 0x00;
    [BLEUtility writeCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:&data length:1]];
    self.imageDetectTimer = [NSTimer scheduledTimerWithTimeInterval:1.5f target:self selector:@selector(imageDetectTimerTick:) userInfo:nil repeats:NO];
    self.imgVersion = 0xFFFF;
}

-(void) deconfigureProfile {
    NSLog(@"Deconfiguring OAD Profile");
    CBUUID *sUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Service UUID"]];
    CBUUID *cUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Notify UUID"]];
    [BLEUtility setNotificationForCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID enable:YES];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error
{
    fprintf(stderr,"std\n");
}
-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(nonnull CBCharacteristic *)characteristic error:(nullable NSError *)error
{
    fprintf(stderr,"notify");
}
// IMPORTANT:
// This is the time delay between sending packets. If it is dropping packets increase the DELAY value
#define DELAY 0.25
-(void) uploadImage:(NSString *)filename {
    self.inProgramming = YES;
    self.canceled = NO;
    
    unsigned char imageFileData[self.imageFile.length];
    [self.imageFile getBytes:imageFileData length:self.imageFile.length];
    uint8_t requestData[OAD_IMG_HDR_SIZE + 2 + 2]; // 12Bytes
    
    for(int ii = 0; ii < 20; ii++) {
        NSLog(@"%02hhx",imageFileData[ii]);
    }

    
    img_hdr_t imgHeader;
    memcpy(&imgHeader, &imageFileData[0 + OAD_IMG_HDR_OSET], sizeof(img_hdr_t));
    
    
    
    requestData[0] = LO_UINT16(imgHeader.ver);
    requestData[1] = HI_UINT16(imgHeader.ver);
    
    requestData[2] = LO_UINT16(imgHeader.len);
    requestData[3] = HI_UINT16(imgHeader.len);
    
    NSLog(@"Image version = %04hx, len = %04hx",imgHeader.ver,imgHeader.len);
    
    memcpy(requestData + 4, &imgHeader.uid, sizeof(imgHeader.uid));
    
    requestData[OAD_IMG_HDR_SIZE + 0] = LO_UINT16(12);
    requestData[OAD_IMG_HDR_SIZE + 1] = HI_UINT16(12);
    
    requestData[OAD_IMG_HDR_SIZE + 2] = LO_UINT16(15);
    requestData[OAD_IMG_HDR_SIZE + 1] = HI_UINT16(15);
    
    CBUUID *sUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Service UUID"]];
    CBUUID *cUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Notify UUID"]];
    [BLEUtility setNotificationForCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID enable:YES];
    [BLEUtility writeCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:requestData length:OAD_IMG_HDR_SIZE + 2 + 2]];
    
    self.nBlocks = imgHeader.len / (OAD_BLOCK_SIZE / HAL_FLASH_WORD_SIZE);
    self.nBytes = imgHeader.len * HAL_FLASH_WORD_SIZE;
    self.iBlocks = 0;
    self.iBytes = 0;
    
    
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(programmingTimerTick:) userInfo:nil repeats:NO];
}

-(void) programmingTimerTick:(NSTimer *)timer {
    if (self.canceled) {
        self.canceled = FALSE;
        return;
    }
    
    unsigned char imageFileData[self.imageFile.length];
    [self.imageFile getBytes:imageFileData length:self.imageFile.length];
    
    //Prepare Block
    uint8_t requestData[2 + OAD_BLOCK_SIZE];
    
    // This block is run 4 times, this is needed to get CoreBluetooth to send consequetive packets in the same connection interval.
    for (int ii = 0; ii < 4; ii++) {
        
        requestData[0] = LO_UINT16(self.iBlocks);
        requestData[1] = HI_UINT16(self.iBlocks);
        
        memcpy(&requestData[2] , &imageFileData[self.iBytes], OAD_BLOCK_SIZE);
        
        CBUUID *sUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Service UUID"]];
        CBUUID *cUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Block Request UUID"]];
        
        [BLEUtility writeNoResponseCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:requestData length:2 + OAD_BLOCK_SIZE]];
        
        self.iBlocks++;
        self.iBytes += OAD_BLOCK_SIZE;
        
        if(self.iBlocks == self.nBlocks) {
            self.inProgramming = NO;
            if ([self.delegate respondsToSelector:@selector(BacTrackOADUploadComplete)]) {
                [self.delegate BacTrackOADUploadComplete];
            }
            return;
        }
        else {
            if (ii == 3)[NSTimer scheduledTimerWithTimeInterval:DELAY target:self selector:@selector(programmingTimerTick:) userInfo:nil repeats:NO];
        }
    }

    // Tell delegate how long it will take to complete
    float secondsPerBlock = DELAY / 4;
    float secondsLeft = (float)(self.nBlocks - self.iBlocks) * secondsPerBlock;
    float percentageLeft = (float)((float)self.iBlocks / (float)self.nBlocks);
    NSNumber * seconds = [NSNumber numberWithFloat:secondsLeft];
    NSNumber * percentage = [NSNumber numberWithFloat:percentageLeft];
    if ([self.delegate respondsToSelector:@selector(BacTrackOADUploadTimeLeft:withPercentage:)]) {
        [self.delegate BacTrackOADUploadTimeLeft:seconds withPercentage:percentage];
    }
    
    NSLog(@".");
}


-(void) didUpdateValueForProfile:(CBCharacteristic *)characteristic {
    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Notify UUID"]]]) {
        if (self.imgVersion == 0xFFFF) {
            unsigned char data[characteristic.value.length];
            [characteristic.value getBytes:&data length:characteristic.value.length];
            self.imgVersion = ((uint16_t)data[1] << 8 & 0xff00) | ((uint16_t)data[0] & 0xff);
            NSLog(@"self.imgVersion : %04hx",self.imgVersion);
        }
        NSLog(@"OAD Image notify : %@",characteristic.value);
    }
}
-(void) didWriteValueForProfile:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        // Dropping writeWithoutReponse packets. Stop the firmware upload and notify the delegate
        self.canceled = YES;
        
        if (self.inProgramming) {
            if ([self.delegate respondsToSelector:@selector(BacTrackOADUploadFailed)]) {
                [self.delegate BacTrackOADUploadFailed];
            }
        }
        
        self.inProgramming = NO;
    }
    else {
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Notify UUID"]]] && readyToInitiateImageTransfer ==TRUE) {
            readyToInitiateImageTransfer = FALSE;
            // Ready to send firmware packets
            [self firmwareReadyToUpdate];
        }
    }
    
    NSLog(@"didWriteValueForProfile : %@",characteristic);
}

-(void)deviceDisconnected:(CBPeripheral *)peripheral {
    if ([peripheral isEqual:self.d.p] && self.inProgramming) {
        // Cancel firmware upload
        self.canceled = YES;
        self.inProgramming = NO;
    }
}


-(BOOL)validateImage:(NSString *)filename {
    self.imageFile = [NSData dataWithContentsOfFile:filename];
    NSLog(@"Loaded firmware \"%@\"of size : %lu",filename,(unsigned long)self.imageFile.length);
    if ([self isCorrectImage]) {
        [self uploadImage:filename];
        return YES;
    }
    else {
        // Invalid image
        return NO;
    }
}
-(BOOL) isCorrectImage {
    unsigned char imageFileData[self.imageFile.length];
    [self.imageFile getBytes:imageFileData length:self.imageFile.length];
    
    img_hdr_t imgHeader;
    memcpy(&imgHeader, &imageFileData[0 + OAD_IMG_HDR_OSET], sizeof(img_hdr_t));
    
    if ((imgHeader.ver & 0x01) != (self.imgVersion & 0x01)) return YES;
    return NO;
}

-(void) imageDetectTimerTick:(NSTimer *)timer {
    //IF we have come here, the image userID is B.
    NSLog(@"imageDetectTimerTick:");
    CBUUID *sUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Service UUID"]];
    CBUUID *cUUID = [CBUUID UUIDWithString:[self.d.setupData valueForKey:@"OAD Image Notify UUID"]];
    readyToInitiateImageTransfer = TRUE;
    unsigned char data = 0x01;
    [BLEUtility writeCharacteristic:self.d.p sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:&data length:1]];
}

@end
