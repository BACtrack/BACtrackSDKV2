//
//  iOS7ProgressAlert.m
//  NeuroTrek Test Tool
//
//  Created by Raymond Kampmeier on 10/21/13.
//  Copyright (c) 2013 Punch Through Design. All rights reserved.
//

#import "iOS7ProgressAlert.h"

@implementation iOS7ProgressAlert

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

- (void)show
{
    self.containerView =[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 280.0f, 80.0f)];
    self.progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.label1 = [[UILabel alloc]init];
    self.label2 = [[UILabel alloc]init];
    self.label1.textColor = [UIColor blackColor];
    self.label2.textColor = [UIColor blackColor];
    self.label1.backgroundColor = [UIColor clearColor];
    self.label2.backgroundColor = [UIColor clearColor];
    self.label1.font = [UIFont boldSystemFontOfSize:14.0f];
    self.label2.font = [UIFont boldSystemFontOfSize:14.0f];
    self.label1.textAlignment = NSTextAlignmentCenter;
    self.label2.textAlignment = NSTextAlignmentCenter;
    
    self.progressBar.frame = CGRectMake(15, 10, 250, 10);
    self.label1.frame = CGRectMake(15,20,250,15);
    self.label2.frame = CGRectMake(15,40,250,15);
    
    [self.containerView addSubview:self.progressBar];
    [self.containerView addSubview:self.label1];
    [self.containerView addSubview:self.label2];
    
    [self setContainerView:self.containerView];

    [super show];
}

@end
