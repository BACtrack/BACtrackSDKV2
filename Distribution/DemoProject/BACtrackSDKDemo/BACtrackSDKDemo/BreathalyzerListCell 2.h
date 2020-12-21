//
//  BreathalyzerListCell.h
//  BACtrack
//
//  Copyright (c) 2018 KHN Solutions LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BreathalyzerListCell : UITableViewCell
{
}

@property (retain, nonatomic) IBOutlet UILabel *breathalyzerTypeLabel;
@property (retain, nonatomic) IBOutlet UILabel *breathalyzerUUIDLabel;

+ (BreathalyzerListCell *) cell;
+ (NSString *) staticReuseIdentifier;
- (NSString *) reuseIdentifier;

@end
