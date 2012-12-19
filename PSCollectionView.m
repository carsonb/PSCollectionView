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
	
	UIInterfaceOrientation _orientation;
	
	NSMutableArray *_colXOffsets;
	NSMutableArray *_colHeights;
	
	NSMutableSet *_reuseableViews;
	
	NSMutableArray *_items; //position is by index, value is PSCollectionViewLayoutAttribute objects
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
		
        _orientation = [UIApplication sharedApplication].statusBarOrientation;
        _reuseableViews = [NSMutableSet set];
		_items = [NSMutableArray array];
		
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

#pragma mark - Reset

- (void)reloadData
{
	for (PSCollectionViewLayoutAttributes *attributes in _items) {
		[self enqueueReusableView:attributes.visibleCell];
	}
	[_items removeAllObjects];
	
    [self invalidateLayout];
}

#pragma mark - View

- (void)invalidateLayout
{
	[_items enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(PSCollectionViewLayoutAttributes *attributes, NSUInteger idx, BOOL *stop) {
		attributes.valid = NO;
		attributes.frame = CGRectZero;
	}];
	
	self.numCols = UIInterfaceOrientationIsPortrait(_orientation) ? self.numColsPortrait : self.numColsLandscape;
	
	//reset the column offsets
	_colXOffsets = nil;
	
	[self resetColumnHeights];
	self.colWidth = floorf((self.width - self.margin * (self.numCols + 1)) / self.numCols);
}

- (void)resetColumnHeights
{
	_colHeights = [NSMutableArray arrayWithCapacity:self.numCols];
	for (int i = 0; i < self.numCols; i++) {
		[_colHeights addObject:@(self.headerView.height + self.margin)];
	}
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
	if ([_items count] == 0 && self.emptyView) {
		self.emptyView.frame = CGRectMake(self.margin, self.margin, self.width - self.margin * 2, self.height - self.margin * 2);
		self.emptyView.hidden = NO;
	} else {
		self.emptyView.hidden = YES;
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
	[_items enumerateObjectsUsingBlock:^(PSCollectionViewLayoutAttributes *itemAttributes, NSUInteger idx, BOOL *stop) {
		if (itemAttributes.valid == NO) {
			//ensure we have the height for this item
			CGFloat height = itemAttributes.frame.size.height;
			if (height == 0.0f) {
				height = [self.collectionViewDataSource heightForViewAtIndex:idx];
			}
			
			//find the shortest column
			NSUInteger shortestColumn = [self shortestColumn];
			CGFloat colXOffset = [_colXOffsets[shortestColumn] floatValue];
			CGFloat colHeight = [_colHeights[shortestColumn] floatValue];
			CGRect frame = CGRectMake(colXOffset, colHeight, self.colWidth, height);
			itemAttributes.frame = frame;
			itemAttributes.currentColumn = shortestColumn;
			itemAttributes.valid = YES;
			
			//update the column heights
			_colHeights[shortestColumn] = @(colHeight + height + self.margin);
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
	
	//Lays out items that are now visible and hides cells that are no longer visible
	CGRect visibleRect = CGRectMake(self.contentOffset.x, self.contentOffset.y, self.width, self.height);
	for (NSInteger i = 0; i < [_items count]; i++) {
		PSCollectionViewLayoutAttributes *itemAttributes = _items[i];
		BOOL visibleCell = CGRectIntersectsRect(visibleRect, itemAttributes.frame);
		if (visibleCell == NO && itemAttributes.visibleCell) {
			//Cell isn't visible, hide it
			[self enqueueReusableView:itemAttributes.visibleCell];
			itemAttributes.visibleCell = nil;
		} else if (visibleCell && itemAttributes.visibleCell == nil) {
			//Cell is now visible, add it in
            PSCollectionViewCell *newCell = [self.collectionViewDataSource collectionView:self viewAtIndex:i];
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

- (void)insertItemAtEnd
{
	[self insertItemAtIndex:[_items count]];
}

- (void)insertItemAtIndex:(NSUInteger)index
{
	PSCollectionViewLayoutAttributes *attributes = [[PSCollectionViewLayoutAttributes alloc] init];
	[_items insertObject:attributes atIndex:index];
	
	[self invalidateLayoutOfItemsAfterIndex:index];
	
	//erform layout if not in a batch update
	if (_batchUpdateInProgress == NO) {
		[self performLayout];
	}
}

- (void)removeItemAtIndex:(NSUInteger)index
{
	PSCollectionViewLayoutAttributes *attributes = _items[index];
	[self enqueueReusableView:attributes.visibleCell];
	
	[_items removeObjectAtIndex:index];
	[self invalidateLayoutOfItemsAfterIndex:index];
	
	//perform layout if not in a batch update
	if (_batchUpdateInProgress == NO) {
		[self performLayout];
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

- (void)invalidateLayoutOfItemsAfterIndex:(NSUInteger)index
{
	for (int i=index; i < [_items count]; i++) {
		PSCollectionViewLayoutAttributes *attributes = _items[i];
		attributes.valid = NO;
	}
	
	//get the max Y values from the previous elements in each column (only need to get numCols number of elements)
	//this does not update the content size since that will be done in performLayout once all the batched changes are applied
	//calculate until all columns have been updated
	[self resetColumnHeights];
	NSMutableIndexSet *completedColumns = [NSMutableIndexSet indexSet];
	NSInteger i = index - 1;
	while (i >= 0) {
		PSCollectionViewLayoutAttributes *attributes = _items[i];
		if (attributes.valid && [completedColumns containsIndex:attributes.currentColumn] == NO) {
			_colHeights[attributes.currentColumn] = @(CGRectGetMaxY(attributes.frame) + self.margin);
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
	NSUInteger longestColumn = [self longestColumn];
	CGFloat longestColumnHeight = [_colHeights[longestColumn] floatValue];
	
	if (self.footerView) {
		//position the footer view correctly
		self.footerView.frame = CGRectMake(0, longestColumnHeight, self.width, self.footerView.height);
		
		longestColumnHeight += self.footerView.frame.size.height;
	}
	self.contentSize = CGSizeMake(self.width, longestColumnHeight);
}

#pragma mark - Helpers

- (NSUInteger)shortestColumn
{
	NSInteger col = 0;
	CGFloat minHeight = [_colHeights[col] floatValue];
	for (int i = 1; i < [_colHeights count]; i++) {
		CGFloat colHeight = [_colHeights[i] floatValue];
		if (colHeight < minHeight) {
			col = i;
			minHeight = colHeight;
		}
	}
	return col;
}

- (NSUInteger)longestColumn
{
	NSInteger col = 0;
	CGFloat maxHeight = [_colHeights[col] floatValue];
	for (int i = 1; i < [_colHeights count]; i++) {
		CGFloat colHeight = [_colHeights[i] floatValue];
		if (colHeight > maxHeight) {
			col = i;
			maxHeight = colHeight;
		}
	}
	return col;
}

#pragma mark - Reusing Views

- (PSCollectionViewCell *)dequeueReusableView
{
    PSCollectionViewCell *view = [_reuseableViews anyObject];
    if (view) {
        // Found a reusable view, remove it from the set
        [_reuseableViews removeObject:view];
    }
    return view;
}

- (void)enqueueReusableView:(PSCollectionViewCell *)view
{
	if (view == nil) {
		return;
	}
	
	[view prepareForReuse];
    view.frame = CGRectZero;
	view.alpha = 1.0f;
    [_reuseableViews addObject:view];
    [view removeFromSuperview];
}

#pragma mark - Gesture Recognizer

- (void)didSelectView:(UITapGestureRecognizer *)gestureRecognizer
{
	CGPoint tapPoint = [gestureRecognizer locationInView:self];
	
	__block PSCollectionViewLayoutAttributes *selectedCell = nil;
	__block NSUInteger selectedIndex = 0;
	[_items enumerateObjectsUsingBlock:^(PSCollectionViewLayoutAttributes *candidate, NSUInteger idx, BOOL *stop) {
		if (candidate.valid && CGRectContainsPoint(candidate.frame, tapPoint)) {
			selectedCell = candidate;
			selectedIndex = idx;
			*stop = YES;
		}
	}];
	
	PSCollectionViewCell *cell = selectedCell.visibleCell;
	if (cell) {
		[self.collectionViewDelegate collectionView:self didSelectView:cell atIndex:selectedIndex];
	}
}

@end
