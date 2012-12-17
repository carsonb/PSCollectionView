//
//  PSCollectionViewLayoutAttributes.h
//  ShopByShopify
//
//  Created by Adam Becevello on 2012-12-14.
//  Copyright (c) 2012 Shopify Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PSCollectionViewCell.h"

@interface PSCollectionViewLayoutAttributes : NSObject

@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) NSUInteger currentColumn;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) BOOL valid;
@property (nonatomic, assign) BOOL previouslyVisible;

@property (nonatomic, strong) PSCollectionViewCell *visibleCell;

@end
