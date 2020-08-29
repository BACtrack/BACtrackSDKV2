//
//  HeatCountNormalizer.m
//  BacTrackManagement
//
//  Created by Raymond Kampmeier on 6/6/14.
//  Copyright (c) 2014 KHN Solutions LLC. All rights reserved.
//

#import "HeatCountNormalizer.h"

@implementation HeatCountNormalizer

+(NSNumber*)normalizeHeatCount:(NSNumber*)count{
    /*
    NSInteger icount = [count integerValue];
    NSInteger result = 0;
    if(icount > 40){
        NSInteger delta = icount - 40;
        result = (int)(delta * 2.0f + 20);
    }else if(icount > 30){
        NSInteger delta = icount - 30;
        result = (int)(delta * 1.0f + 10);
    }else if(icount >= 0){
        result = (int)(icount * (1.0/3.0));
    }
    
    return @((int)(result/2.0));
     */
    float fcount = [count floatValue];
    return @(fcount/2.5);
}

@end
