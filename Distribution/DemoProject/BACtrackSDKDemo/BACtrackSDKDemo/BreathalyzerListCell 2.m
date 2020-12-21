//
//  BreathalyzerListCell.m
//  BACtrack
//
//  Copyright (c) 2018 KHN Solutions LLC. All rights reserved.
//

#import "BreathalyzerListCell.h"

@implementation BreathalyzerListCell


+ (NSString *)staticReuseIdentifier
{
    return @"BreathalyzerListCell";
}

- (NSString *)reuseIdentifier
{
    return [BreathalyzerListCell staticReuseIdentifier];
}

// Call this to get an autoreleased cell.
+ (BreathalyzerListCell *) cell
{
    BreathalyzerListCell *cell = nil;
    NSArray *top_level = [[NSBundle mainBundle] loadNibNamed:@"BreathalyzerListCell" owner:self options:nil];
    for(id obj in top_level)
    {
        if([obj isKindOfClass:[BreathalyzerListCell class]])
        {
            cell = (BreathalyzerListCell *) obj;
            [cell setup];
            break;
        }
    }
    return cell;
}

// Make sure setup gets called from each of the various possible initializers.
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)awakeFromNib
{
    // Initialization code
    [super awakeFromNib];
    [self setup];
}

- (void) setup
{
    
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    if (selected)
    {
        self.contentView.backgroundColor = [UIColor colorWithRed:20.0/255.0 green:173.0/255.0 blue:228.0/255.0 alpha:1];
        self.breathalyzerTypeLabel.textColor = [UIColor whiteColor];
        self.breathalyzerUUIDLabel.textColor = [UIColor whiteColor];
    }
    else
    {
        self.contentView.backgroundColor = [UIColor clearColor];
        self.breathalyzerTypeLabel.textColor = [UIColor colorWithRed:2.0/255.0 green:45.0/255.0 blue:68.0/255.0 alpha:1];
        self.breathalyzerUUIDLabel.textColor = [UIColor colorWithRed:20.0/255.0 green:173.0/255.0 blue:228.0/255.0 alpha:1];
    }
}

@end
