//
// PSCollectionView.m
//
// Copyright (c) 2012 Peter Shih (http://petershih.com)
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "PSCollectionView.h"
#import "PSCollectionViewCell.h"
#import "PSCollectionViewLayoutAttributes.h"

#define kDefaultMargin 8.0
#define kAnimationDuration 0.3f

#define kPSCollectionViewCellReuseBufferRows 5

#pragma mark - UIView Category

@interface UIView (PSCollectionView)

@property(nonatomic, assign) CGFloat left;
@property(nonatomic, assign) CGFloat top;
@property(nonatomic, assign, readonly) CGFloat right;
@property(nonatomic, assign, readonly) CGFloat bottom;
@property(nonatomic, assign) CGFloat width;
@property(nonatomic, assign) CGFloat height;

@end

@implementation UIView (PSCollectionView)

- (CGFloat)left {
    return self.frame.origin.x;
}

- (void)setLeft:(CGFloat)x {
    CGRect frame = self.frame;
    frame.origin.x = x;
    self.frame = frame;
}

- (CGFloat)top {
    return self.frame.origin.y;
}

- (void)setTop:(CGFloat)y {
    CGRect frame = self.frame;
    frame.origin.y = y;
    self.frame = frame;
}

- (CGFloat)right {
    return self.frame.origin.x + self.frame.size.width;
}

- (CGFloat)bottom {
    return self.frame.origin.y + self.frame.size.height;
}

- (CGFloat)width {
    return self.frame.size.width;
}

- (void)setWidth:(CGFloat)width {
    CGRect frame = self.frame;
    frame.size.width = width;
    self.frame = frame;
}

- (CGFloat)height {
    return self.frame.size.height;
}

- (void)setHeight:(CGFloat)height {
    CGRect frame = self.frame;
    frame.size.height = height;
    self.frame = frame;
}

@end

#pragma mark - Gesture Recognizer

// This is just so we know that we sent this tap gesture recognizer in the delegate
@interface PSCollectionViewTapGestureRecognizer : UITapGestureRecognizer
@end

@implementation PSCollectionViewTapGestureRecognizer
@end


@interface PSCollectionView ()

@property (nonatomic, assign, readwrite) CGFloat colWidth;
@property (nonatomic, assign, readwrite) NSInteger numCols;

@end

@implementation PSCollectionView {
	BOOL _batchUpdateInProgress;
	
	NSInteger _numSections;
	
	UIInterfaceOrientation _orientation;
	
	NSMutableArray *_colXOffsets;
	
	NSMutableArray *_sectionColumnHeights; //contains an array of arrays, first array is positioned by section number, values are the heights of each column within each section
	
	NSMutableDictionary *_reusableViews;
	
	NSMutableDictionary *_sectionItems; //key is section number, value is array with position is by index, value is PSCollectionViewLayoutAttribute objects
}

#pragma mark - Init/Memory

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.alwaysBounceVertical = YES;
		
		self.margin = kDefaultMargin;
        
        self.colWidth = 0.0;
        self.numCols = 0;
        self.numColsPortrait = 0;
        self.numColsLandscape = 0;
		self.animateLayoutChanges = YES;
		
		_numSections = 1;
        _orientation = [UIApplication sharedApplication].statusBarOrientation;
		_reusableViews = [NSMutableDictionary dictionary];
		_sectionItems = [NSMutableDictionary dictionary];
		
		PSCollectionViewTapGestureRecognizer *recognizer = [[PSCollectionViewTapGestureRecognizer alloc] initWithTarget:self action:@selector(didSelectView:)];
		[recognizer setCancelsTouchesInView:NO];
		[self addGestureRecognizer:recognizer];
		
		[self invalidateLayout];
    }
    return self;
}

- (void)dealloc
{
    // clear delegates
    self.delegate = nil;
    self.collectionViewDataSource = nil;
    self.collectionViewDelegate = nil;
}

#pragma mark - Setters

- (void)setNumColsLandscape:(NSInteger)numColsLandscape
{
	_numColsLandscape = numColsLandscape;
	[self invalidateLayout];
}

- (void)setNumColsPortrait:(NSInteger)numColsPortrait
{
	_numColsPortrait = numColsPortrait;
	[self invalidateLayout];
}

- (void)setMargin:(CGFloat)margin
{
	_margin = margin;
	[self invalidateLayout];
}

- (void)setLoadingView:(UIView *)loadingView {
	[_loadingView removeFromSuperview];
    _loadingView = nil;
	
	if (loadingView) {
		_loadingView = loadingView;
		[self addSubview:_loadingView];
	}
	
	[self invalidateLayout];
}

- (void)setEmptyView:(UIView *)emptyView {
	[_emptyView removeFromSuperview];
	_emptyView = nil;
	
	if (emptyView) {
		_emptyView = emptyView;
		_emptyView.hidden = YES;
		[self addSubview:_emptyView];
	}
	
	[self invalidateLayout];
}

- (void)setHeaderView:(UIView *)headerView {
	[_headerView removeFromSuperview];
	_headerView = nil;
	
	if (headerView) {
		_headerView = headerView;
		[self addSubview:_headerView];
	}
	
	[self invalidateLayout];
}

- (void)setFooterView:(UIView *)footerView {
	[_footerView removeFromSuperview];
	_footerView = nil;
	
	if (footerView) {
		_footerView = footerView;
		[self addSubview:_footerView];
	}
	
	[self invalidateLayout];
}

- (void)setFrame:(CGRect)frame
{
	[super setFrame:frame];
	[self invalidateLayout];
}

#pragma mark - Reset

- (void)reloadData
{
	for (NSArray *sectionItems in [_sectionItems allValues]) {
		for (PSCollectionViewLayoutAttributes *attributes in sectionItems) {
			[self enqueueReusableView:attributes.visibleCell];
		}
	}
	
	_sectionItems = [NSMutableDictionary dictionary];
	
	_numSections = [self.collectionViewDataSource numberOfSectionsInCollectionView:self];
	for (NSUInteger i = 0; i < _numSections; i++) {
		//recreate items for the number of views that will appear in the grid
		NSInteger numCells = [self.collectionViewDataSource collectionView:self numberOfViewsInSection:i];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:numCells];
		for (NSUInteger i = 0; i < numCells; i++) {
			[items addObject:[[PSCollectionViewLayoutAttributes alloc] init]];
		}
		[_sectionItems setObject:items forKey:@(i)];
	}
	
    [self invalidateLayout];
	[self setNeedsLayout];
}

#pragma mark - View

- (void)invalidateItemLayoutAttributes:(PSCollectionViewLayoutAttributes *)attributes
{
	attributes.valid = NO;
	attributes.frame = CGRectZero;
}

- (void)invalidateLayout
{
	for (NSArray *sectionItems in [_sectionItems allValues]) {
		[sectionItems enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(PSCollectionViewLayoutAttributes *attributes, NSUInteger idx, BOOL *stop) {
			[self invalidateItemLayoutAttributes:attributes];
		}];
	}
	
	self.numCols = UIInterfaceOrientationIsPortrait(_orientation) ? self.numColsPortrait : self.numColsLandscape;
	
	//reset the column offsets
	_colXOffsets = nil;
	
	[self resetColumnHeights];
	if (self.numCols == 0) {
		self.colWidth = 0.0f;
	} else {
		self.colWidth = floorf((self.width - self.margin * (self.numCols + 1)) / self.numCols);
	}
}

- (void)resetColumnHeights
{
	//sections are assumed to be the same height, this will change as items are added to each sections
	_sectionColumnHeights = [NSMutableArray array];
	for (NSUInteger i = 0; i < _numSections; i++) {
		[_sectionColumnHeights addObject:@0.0f]; //ensure the array has a position for this section, this simplifies the resetColumnHeightsInSection method
		[self resetColumnHeightsInSection:i];
	}
}

- (void)resetColumnHeightsInSection:(NSUInteger)section
{
	//sections are assumed to be the same height, this will change as items are added to each sections
	NSNumber *marginHeight = @(self.margin);
	NSMutableArray *colHeights = [NSMutableArray array];
	for (NSUInteger i = 0; i < self.numCols; i++) {
		[colHeights addObject:marginHeight];
	}
	_sectionColumnHeights[section] = colHeights;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
	
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (_orientation != orientation) {
        _orientation = orientation;
		[self invalidateLayout];
	}
	
	[self performLayout];
}

- (void)performLayout
{
	__block BOOL recalculateContentSize = NO;
	
	//layout header
	CGSize headerSize = [self.headerView sizeThatFits:CGSizeMake(self.width, CGFLOAT_MAX)];
	if (self.headerView.height != headerSize.height) {
		self.headerView.height = headerSize.height;
		self.headerView.width = self.width;
		
		//since the height was changed, the layout needs to be adjusted to handle it
		[self invalidateLayout];
		recalculateContentSize = YES;
	}
	
	//handle displaying and hiding the empty view
	if (self.emptyView) {
		BOOL hasItems = NO;
		for (NSArray *sectonItems in [_sectionItems allValues]) {
			if ([sectonItems count] > 0) {
				hasItems = YES;
			}
		}
		if (hasItems == NO) {
			self.emptyView.frame = CGRectMake(self.margin, self.margin, self.width - self.margin * 2, self.height - self.margin * 2);
			self.emptyView.hidden = NO;
		} else {
			self.emptyView.hidden = YES;
		}
	}
	
	if (_colXOffsets == nil) {
		_colXOffsets = [NSMutableArray arrayWithCapacity:self.numCols];
		CGFloat left = self.margin;
		for (int i = 0; i < self.numCols; i++) {
			[_colXOffsets addObject:@(left)];
			left += self.colWidth + self.margin;
		}
	}
	
	//calculate the positions of all cells, but skip the cells that had no change
	//a cell has a change if its layout is marked as invalid
	[_sectionItems enumerateKeysAndObjectsUsingBlock:^(NSNumber *sectionNumber, NSArray *sectionItems, BOOL *stop) {
		NSUInteger section = [sectionNumber integerValue];
		[sectionItems enumerateObjectsUsingBlock:^(PSCollectionViewLayoutAttributes *itemAttributes, NSUInteger idx, BOOL *stop) {
			if (itemAttributes.valid == NO) {
				NSIndexPath *indexPath = [NSIndexPath indexPathForItem:idx inSection:section];
				
				//ensure we have the height for this item
				CGFloat height = itemAttributes.frame.size.height;
				if (height == 0.0f) {
					height = [self.collectionViewDataSource heightForViewAtIndexPath:indexPath];
				}
				
				//find the shortest column
				NSUInteger shortestColumn = [self shortestColumnInSection:section];
				CGFloat colXOffset = [_colXOffsets[shortestColumn] floatValue];
				CGFloat yOffset = [self yOffsetForItemInSection:section column:shortestColumn];
				CGRect frame = CGRectMake(colXOffset, yOffset, self.colWidth, height);
				itemAttributes.frame = frame;
				itemAttributes.currentColumn = shortestColumn;
				itemAttributes.valid = YES;
				
				//update the column heights
				[self updateHeightOfColumn:shortestColumn inSection:section withAdditionalHeight:height + self.margin];
				recalculateContentSize = YES;
				
				if (self.animateLayoutChanges && itemAttributes.previouslyVisible && itemAttributes.visibleCell) {
					[UIView animateWithDuration:kAnimationDuration animations:^{
						itemAttributes.visibleCell.frame = itemAttributes.frame;
					}];
				} else {
					[UIView setAnimationsEnabled:NO];
					itemAttributes.visibleCell.frame = itemAttributes.frame;
					[UIView setAnimationsEnabled:YES];
				}
			}
		}];
	}];
	
	
	//Lays out items that are now visible and hides cells that are no longer visible
	CGRect visibleRect = CGRectMake(self.contentOffset.x, self.contentOffset.y, self.width, self.height);
	[_sectionItems enumerateKeysAndObjectsUsingBlock:^(NSNumber *sectionNumber, NSArray *sectionItems, BOOL *stop) {
		for (NSUInteger i = 0; i < [sectionItems count]; i++) {
			PSCollectionViewLayoutAttributes *itemAttributes = sectionItems[i];
			BOOL visibleCell = CGRectIntersectsRect(visibleRect, itemAttributes.frame);
			if (visibleCell == NO && itemAttributes.visibleCell) {
				//Cell isn't visible, hide it
				[self enqueueReusableView:itemAttributes.visibleCell];
				itemAttributes.visibleCell = nil;
			} else if (visibleCell && itemAttributes.visibleCell == nil) {
				//Cell is now visible, add it in
				NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:[sectionNumber integerValue]];
				PSCollectionViewCell *newCell = [self.collectionViewDataSource collectionView:self viewAtIndexPath:indexPath];
				itemAttributes.visibleCell = newCell;
				[self addSubview:newCell];
				
				if (self.animateLayoutChanges && itemAttributes.previouslyVisible == NO) {
					itemAttributes.previouslyVisible = YES;
					[UIView setAnimationsEnabled:NO];
					newCell.frame = itemAttributes.frame;
					newCell.alpha = 0.0f;
					[UIView setAnimationsEnabled:YES];
					[UIView animateWithDuration:kAnimationDuration delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:^{
						newCell.alpha = 1.0f;
					} completion:nil];
				} else {
					[UIView setAnimationsEnabled:NO];
					newCell.frame = itemAttributes.frame;
					[UIView setAnimationsEnabled:YES];
				}
			}
		}
	}];
	
	//layout footer
	CGSize footerSize = [self.footerView sizeThatFits:CGSizeMake(self.width, CGFLOAT_MAX)];
	if (self.footerView.height != footerSize.height) {
		self.footerView.height = footerSize.height;
		recalculateContentSize = YES;
	}
	
	//only update content size when it is needed
	if (recalculateContentSize) {
		[self updateContentSizeForColumnHeightChange];
	}
}

- (void)insertItemAtIndexPath:(NSIndexPath *)indexPath
{
	PSCollectionViewLayoutAttributes *attributes = [[PSCollectionViewLayoutAttributes alloc] init];
	
	NSNumber *section = @(indexPath.section);
	NSMutableArray *sectionItems = [_sectionItems objectForKey:section];
	if (sectionItems == nil) {
		sectionItems = [NSMutableArray array];
		[_sectionItems setObject:sectionItems forKey:section];
	}
	[sectionItems insertObject:attributes atIndex:indexPath.item];
	
	[self invalidateLayoutOfItemsAfterIndexPath:indexPath];
	
	//erform layout if not in a batch update
	if (_batchUpdateInProgress == NO) {
		[self performLayout];
	}
}

- (void)removeItemAtIndexPath:(NSIndexPath *)indexPath
{
	NSNumber *section = @(indexPath.section);
	NSMutableArray *sectionItems = [_sectionItems objectForKey:section];
	if (sectionItems) {
		PSCollectionViewLayoutAttributes *attributes = sectionItems[indexPath.item];
		[self enqueueReusableView:attributes.visibleCell];
		
		[sectionItems removeObjectAtIndex:indexPath.item];
		[self invalidateLayoutOfItemsAfterIndexPath:indexPath];
		
		//perform layout if not in a batch update
		if (_batchUpdateInProgress == NO) {
			[self performLayout];
		}
	}
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(void))completion
{
	_batchUpdateInProgress = YES;
	if (updates) {
		updates();
	}
	//perform layout to apply the changes
	[self performLayout];
	_batchUpdateInProgress = NO;
	if (completion) {
		completion();
	}
}

- (void)invalidateLayoutOfItemsAfterIndexPath:(NSIndexPath *)indexPath
{
	[_sectionItems enumerateKeysAndObjectsUsingBlock:^(NSNumber *sectionNumber, NSMutableArray *sectionItems, BOOL *stop) {
		NSInteger section = [sectionNumber integerValue];
		if (indexPath.section > section) {
			//invalidate all items in this section
			for (PSCollectionViewLayoutAttributes *attributes in sectionItems) {
				[self invalidateItemLayoutAttributes:attributes];
			}
			[self resetColumnHeightsInSection:section];
		} else if (indexPath.section == section) {
			//invalidate only items after this item
			for (int i=indexPath.item; i < [sectionItems count]; i++) {
				PSCollectionViewLayoutAttributes *attributes = sectionItems[i];
				[self invalidateItemLayoutAttributes:attributes];
			}
			[self resetColumnHeightsInSection:section];
		}
	}];	
	
	//get the max Y values from the previous elements in each column (only need to get numCols number of elements)
	//this does not update the content size since that will be done in performLayout once all the batched changes are applied
	//calculate until all columns have been updated
	NSMutableIndexSet *completedColumns = [NSMutableIndexSet indexSet];
	NSInteger i = indexPath.item - 1;
	NSMutableArray *sectionItems = [_sectionItems objectForKey:@(indexPath.section)];
	while (i >= 0) {
		PSCollectionViewLayoutAttributes *attributes = sectionItems[i];
		if (attributes.valid && [completedColumns containsIndex:attributes.currentColumn] == NO) {
			NSMutableArray *colHeights = _sectionColumnHeights[indexPath.section];
			colHeights[attributes.currentColumn] = @(CGRectGetMaxY(attributes.frame) - self.headerView.height + self.margin);
			[completedColumns addIndex:attributes.currentColumn];
		}
		//stop checking if all columns have been updated
		if ([completedColumns count] == self.numCols) {
			break;
		}
		
		i--;
	}
}

- (void)updateContentSizeForColumnHeightChange
{
	//calculate the height of all combined sections
	CGFloat totalHeight = 0.0f;
	
	if (self.headerView) {
		totalHeight += self.headerView.height;
	}
	
	for (NSUInteger i = 0; i < _numSections; i++) {
		totalHeight += [self heightOfLongestColumnInSection:i];
	}
	
	if (self.footerView) {
		//position the footer view correctly
		self.footerView.frame = CGRectMake(0, totalHeight, self.width, self.footerView.height);
		
		totalHeight += self.footerView.frame.size.height;
	}
	self.contentSize = CGSizeMake(self.width, totalHeight);
}

#pragma mark - Helpers

- (CGFloat)yOffsetForItemInSection:(NSUInteger)section column:(NSUInteger)column
{
	//the yoffset is the height of all previous sections, plus the height of the column in the current section
	CGFloat height = 0.0f;
	
	if (self.headerView) {
		height += self.headerView.height;
	}
	
	if (section > 0) {
		for (NSUInteger i = 0; i < section - 1; i++) {
			height += [self heightOfLongestColumnInSection:i];
		}
	}
	
	NSArray *columnHeights = _sectionColumnHeights[section];
	height += [columnHeights[column] floatValue];
	return height;
}

- (void)updateHeightOfColumn:(NSInteger)column inSection:(NSUInteger)section withAdditionalHeight:(CGFloat)height
{
	NSMutableArray *columnHeights = _sectionColumnHeights[section];
	NSNumber *currentHeight = columnHeights[column];
	columnHeights[column] = @([currentHeight floatValue] + height);
}

- (NSUInteger)shortestColumnInSection:(NSUInteger)section
{
	NSInteger col = 0;
	NSMutableArray *sectionColumnHeights = _sectionColumnHeights[section];
	CGFloat minHeight = [sectionColumnHeights[col] floatValue];
	for (int i = 1; i < [sectionColumnHeights count]; i++) {
		CGFloat colHeight = [sectionColumnHeights[i] floatValue];
		if (colHeight < minHeight) {
			col = i;
			minHeight = colHeight;
		}
	}
	return col;
}

- (CGFloat)heightOfLongestColumnInSection:(NSUInteger)section
{
	NSMutableArray *sectionColumnHeights = _sectionColumnHeights[section];
	CGFloat maxHeight = [sectionColumnHeights[0] floatValue];
	for (int i = 1; i < [sectionColumnHeights count]; i++) {
		CGFloat colHeight = [sectionColumnHeights[i] floatValue];
		if (colHeight > maxHeight) {
			maxHeight = colHeight;
		}
	}
	return maxHeight;
}

#pragma mark - Reusing Views

- (PSCollectionViewCell *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier
{
	if ([reuseIdentifier length] == 0) {
		return nil;
	}
	
	NSMutableSet *reusableViewsForIdentifier = [_reusableViews objectForKey:reuseIdentifier];
	if (reusableViewsForIdentifier) {
		PSCollectionViewCell *view = [reusableViewsForIdentifier anyObject];
		if (view) {
			// Found a reusable view, remove it from the set
			[reusableViewsForIdentifier removeObject:view];
			return view;
		}
	}
	return nil;
}

- (void)enqueueReusableView:(PSCollectionViewCell *)view
{
	if (view == nil) {
		return;
	}
	
	[view prepareForReuse];
    view.frame = CGRectZero;
	view.alpha = 1.0f;
	
	NSMutableSet *reusableViewsForIdentifier = [_reusableViews objectForKey:view.reuseIdentifier];
	if (reusableViewsForIdentifier == nil && [view.reuseIdentifier length] > 0) {
		[_reusableViews setObject:[NSMutableSet set] forKey:view.reuseIdentifier];
	}
	[reusableViewsForIdentifier addObject:view];
    [view removeFromSuperview];
}

#pragma mark - Gesture Recognizer

- (void)didSelectView:(UITapGestureRecognizer *)gestureRecognizer
{
	CGPoint tapPoint = [gestureRecognizer locationInView:self];
	
	__block PSCollectionViewLayoutAttributes *selectedCell = nil;
	__block NSIndexPath *selectedIndexPath = nil;
	[_sectionItems enumerateKeysAndObjectsUsingBlock:^(NSNumber *sectionNumber, NSArray *sectionItems, BOOL *stop) {
		[sectionItems enumerateObjectsUsingBlock:^(PSCollectionViewLayoutAttributes *candidate, NSUInteger idx, BOOL *stop) {
			if (candidate.valid && CGRectContainsPoint(candidate.frame, tapPoint)) {
				selectedCell = candidate;
				selectedIndexPath = [NSIndexPath indexPathForItem:idx inSection:[sectionNumber integerValue]];
				*stop = YES;
			}
		}];
	}];
	
	PSCollectionViewCell *cell = selectedCell.visibleCell;
	if (cell) {
		[self.collectionViewDelegate collectionView:self didSelectView:cell atIndexPath:selectedIndexPath];
	}
}

@end
