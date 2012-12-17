//
//  PSCollectionViewLayoutAttributes.m
//  ShopByShopify
//
//  Created by Adam Becevello on 2012-12-14.
//  Copyright (c) 2012 Shopify Inc. All rights reserved.
//

#import "PSCollectionViewLayoutAttributes.h"

@implementation PSCollectionViewLayoutAttributes

- (id)init
{
	self = [super init];
	if (self) {
		self.frame = CGRectZero;
		self.currentColumn = 0;
		self.alpha = 1.0f;
		self.valid = NO;
		self.previouslyVisible = NO;
	}
	return self;
}

@end
