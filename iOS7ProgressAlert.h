//
//  iOS7ProgressAlert.h
//  NeuroTrek Test Tool
//
//  Created by Raymond Kampmeier on 10/21/13.
//  Copyright (c) 2013 Punch Through Design. All rights reserved.
//

#import "CustomIOS7AlertView.h"

@interface iOS7ProgressAlert : CustomIOS7AlertView

@property (strong,nonatomic) UIProgressView *progressBar;
@property (strong,nonatomic) UILabel *label1;
@property (strong,nonatomic) UILabel *label2;

- (void)show;

@end
