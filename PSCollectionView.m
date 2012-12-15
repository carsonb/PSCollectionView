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

@interface PSCollectionViewKey : NSObject <NSCopying>

- (instancetype)initWithInteger:(NSInteger)integer;
+ (PSCollectionViewKey*)keyWithInteger:(NSInteger)integer;

@property (nonatomic, assign) NSInteger key;

@end

@implementation PSCollectionViewKey

- (id)copyWithZone:(NSZone *)zone
{
	PSCollectionViewKey *newKey = [[self class] allocWithZone:zone];
    newKey.key = self.key;
    return newKey;
}

- (instancetype)initWithInteger:(NSInteger)integer
{
	self = [super init];
	if (self) {
		_key = integer;
	}
	return self;
}

+ (PSCollectionViewKey*)keyWithInteger:(NSInteger)integer
{
	return [[PSCollectionViewKey alloc] initWithInteger:integer];
}

- (NSUInteger)hash
{
	return _key;
}

- (BOOL)isEqual:(id)object
{
	return _key == ((PSCollectionViewKey*)object).key;
}

@end

static inline PSCollectionViewKey * PSCollectionKeyForIndex(NSInteger index) {
	return [PSCollectionViewKey keyWithInteger:index];
}

static inline NSInteger PSCollectionIndexForKey(PSCollectionViewKey *key) {
    return key.key;
}

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


@interface PSCollectionView () <UIGestureRecognizerDelegate>

@property (nonatomic, assign, readwrite) CGFloat colWidth;
@property (nonatomic, assign, readwrite) NSInteger numCols;
@property (nonatomic, assign) UIInterfaceOrientation orientation;

@property (nonatomic, strong) NSMutableSet *reuseableViews;
@property (nonatomic, strong) NSMutableDictionary *visibleViews;
@property (nonatomic, strong) NSMutableArray *viewKeysToRemove;
@property (nonatomic, strong) NSMutableDictionary *indexToRectMap;
@property (nonatomic, strong) NSMutableArray *colOffsets;
@property (nonatomic, strong) NSMutableIndexSet *loadedIndices;

@property (nonatomic, assign, readwrite) CGFloat headerViewHeight;

@end

@implementation PSCollectionView {
	BOOL _resetLoadedIndices;
	BOOL _batchUpdateInProgress;
	BOOL _layoutInvalidated;
	
	NSMutableArray *_colXOffsets;
	NSMutableArray *_colHeights;
	
	NSMutableArray *_items; //position is by index, value is PSCollectionViewLayoutAttribute objects
}

#pragma mark - Init/Memory

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.alwaysBounceVertical = YES;
		
		self.margin = kDefaultMargin;
        
        self.colWidth = 0.0;
        self.numCols = 0;
        self.numColsPortrait = 0;
        self.numColsLandscape = 0;
        self.orientation = [UIApplication sharedApplication].statusBarOrientation;
        
        self.reuseableViews = [NSMutableSet set];
        self.visibleViews = [NSMutableDictionary dictionary];
        self.viewKeysToRemove = [NSMutableArray array];
        self.indexToRectMap = [NSMutableDictionary dictionary];
		self.loadedIndices = [NSMutableIndexSet indexSet];
		self.animateLayoutChanges = YES;
		self.headerViewHeight = 0.0f;
		
		PSCollectionViewTapGestureRecognizer *recognizer = [[PSCollectionViewTapGestureRecognizer alloc] initWithTarget:self action:@selector(didSelectView:)];
		[recognizer setCancelsTouchesInView:NO];
		[self addGestureRecognizer:recognizer];
		
		_items = [NSMutableArray array];
		[self invalidateLayout];
    }
    return self;
}

- (void)dealloc {
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
		[self addSubview:_emptyView];
	}
	
	[self relayoutViews];
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

#pragma mark - DataSource

- (void)reloadData
{
	_resetLoadedIndices = YES;
    [self invalidateLayout];
}

#pragma mark - View

- (void)invalidateLayout
{
	[_items enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(PSCollectionViewLayoutAttributes *attributes, NSUInteger idx, BOOL *stop) {
		attributes.valid = NO;
	}];
	
	self.numCols = UIInterfaceOrientationIsPortrait(self.orientation) ? self.numColsPortrait : self.numColsLandscape;
	
	//reset the column offsets
	_colXOffsets = nil;
	
	_colHeights = [NSMutableArray arrayWithCapacity:self.numCols];
	for (int i = 0; i < self.numCols; i++) {
		[_colHeights addObject:@(self.headerViewHeight + self.margin)];
	}
	
	self.colWidth = floorf((self.width - self.margin * (self.numCols + 1)) / self.numCols);
	
	_layoutInvalidated = YES;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
	
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (self.orientation != orientation) {
        self.orientation = orientation;
		
		[self invalidateLayout];
//	} else {
//		//determine if the header has changed height
//		CGSize headerSize = [self.headerView sizeThatFits:CGSizeMake(self.width, CGFLOAT_MAX)];
//		if (self.headerViewHeight != headerSize.height) {
//			self.headerView.height = headerSize.height;
//			self.headerViewHeight = headerSize.height;
//			
//			//need to adjust all the cells and column heights to reflect the new header height
//			[self relayoutViews];
//		}
//		
//		[self removeAndAddCellsIfNecessary];
	}
	
	//TODO: determine if performLayout needs to be done on layoutSubviews
	
	//determine if the header has changed height
	CGSize headerSize = [self.headerView sizeThatFits:CGSizeMake(self.width, CGFLOAT_MAX)];
	if (self.headerViewHeight != headerSize.height) {
		self.headerView.height = headerSize.height;
		self.headerViewHeight = headerSize.height;
		
		//need to adjust all the cells and column heights to reflect the new header height
		[self invalidateLayout];
	}
	
	//TODO: put in animation block?
	if (_layoutInvalidated) {
		[self performLayout];
	}
}

- (void)performLayout
{
	if (_colXOffsets == nil) {
		_colXOffsets = [NSMutableArray arrayWithCapacity:self.numCols];
		CGFloat left = self.margin;
		for (int i = 0; i < self.numCols; i++) {
			[_colXOffsets addObject:@(left)];
			left += self.colWidth + self.margin;
		}
	}
	
	//TODO: handle empty data view
	
	//TODO: layout header
	
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
			itemAttributes.alpha = 1.0f;
			itemAttributes.valid = YES;
			itemAttributes.cell.frame = frame;
			
			//update the column heights
			_colHeights[shortestColumn] = @(colHeight + height + self.margin);
		}
	}];
	
	//TODO: update footer position
	
	//update the content size
	NSUInteger longestColumn = [self longestColumn];
	self.contentSize = CGSizeMake(self.width, [_colHeights[longestColumn] floatValue]);
	
	_layoutInvalidated = NO;
}

- (void)insertItem
{
	[self insertItemAtIndex:[_items count]];
}

- (void)insertItemAtIndex:(NSUInteger)index
{
	PSCollectionViewCell *cell = [self.collectionViewDataSource collectionView:self viewAtIndex:index];
	PSCollectionViewLayoutAttributes *attributes = [[PSCollectionViewLayoutAttributes alloc] init];
	attributes.cell = cell;
	
	//if we are animating layout changes, fade in the cell
	if (self.animateLayoutChanges) {
		attributes.alpha = 0.0f;
	}
	
	[_items insertObject:attributes atIndex:index];
	[self addSubview:cell];
	
	[self invalidateLayoutOfItemsAfterIndex:index];
	
	//erform layout if not in a batch update
	if (_batchUpdateInProgress == NO) {
		[self performLayout];
	}
}

- (void)removeItemAtIndex:(NSUInteger)index
{
	PSCollectionViewLayoutAttributes *attributes = _items[index];
	[self enqueueReusableView:attributes.cell];
	
	[_items removeObjectAtIndex:index];
	[self invalidateLayoutOfItemsAfterIndex:index];
	
	//update the column heights
	[self updateHeightOfColumnsAtIndex:index];
	
	//perform layout if not in a batch update
	if (_batchUpdateInProgress == NO) {
		[self performLayout];
	}
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(void))completion
{
	_batchUpdateInProgress = YES;
	[UIView animateWithDuration:kAnimationDuration animations:^{
		if (updates) {
			updates();
		}
		//perform layout to apply the changes
		[self performLayout];
	} completion:^(BOOL finished) {
		_batchUpdateInProgress = NO;
		if (completion) {
			completion();
		}
	}];
}

- (void)updateHeightOfColumnsAtIndex:(NSUInteger)index
{
	//get the max Y values from the previous elements in each column (only need to get numCols number of elements)
	//TODO: make sure this is iterating the correct number of times
	for (int i = index; i > index - self.numCols && i >=0; i--) {
		PSCollectionViewLayoutAttributes *attributes = _items[i];
		_colHeights[attributes.currentColumn] = @(CGRectGetMaxY(attributes.frame) + self.margin);
	}
}

- (void)invalidateLayoutOfItemsAfterIndex:(NSUInteger)index
{
	for (int i=index; i < [_items count]; i++) {
		PSCollectionViewLayoutAttributes *attributes = _items[i];
		attributes.valid = NO;
	}
}

#pragma mark - Old code after this in the section

- (void)buildColumnOffsetsFromTop:(CGFloat) top
{
	self.colOffsets = [NSMutableArray arrayWithCapacity:self.numCols];
	for (int i = 0; i < self.numCols; i++) {
		[_colOffsets addObject:[NSNumber numberWithFloat:top]];
	}
}

- (NSInteger)findShortestColumn
{
	NSInteger col = 0;
	CGFloat minHeight = [[_colOffsets objectAtIndex:col] floatValue];
	for (int i = 1; i < [_colOffsets count]; i++) {
		CGFloat colHeight = [[_colOffsets objectAtIndex:i] floatValue];
		
		if (colHeight < minHeight) {
			col = i;
			minHeight = colHeight;
		}
	}
	return col;
}

- (void)insertViewRectForIndex:(int)index forKey:(id <NSCopying>)key inColumn:(NSInteger)col
{
	CGFloat left = self.margin + (col * self.margin) + (col * self.colWidth);
	CGFloat top = [[_colOffsets objectAtIndex:col] floatValue];
	CGFloat colHeight = [self.collectionViewDataSource heightForViewAtIndex:index];
	if (colHeight == 0) {
		colHeight = self.margin;
	}
	
	// Add to index rect map
	CGRect viewRect = CGRectMake(left, top, self.colWidth, colHeight);
	[self.indexToRectMap setObject:[NSValue valueWithCGRect:viewRect] forKey:key];
	
	// Update the last height offset for this column
	CGFloat test = top + colHeight + self.margin;
	[_colOffsets replaceObjectAtIndex:col withObject:[NSNumber numberWithFloat:test]];
}

- (CGFloat)updateFooterViewWithTotalHeight:(CGFloat)totalHeight
{
	// Add footerView if exists
    if (self.footerView) {
        self.footerView.width = self.width;
        self.footerView.top = totalHeight;
		
		CGSize footerSize = [self.footerView sizeThatFits:CGSizeMake(self.width, CGFLOAT_MAX)];
		self.footerView.height = footerSize.height;
        totalHeight += self.footerView.height;
    }
	return totalHeight;
}

- (CGFloat)totalHeightFromColOffsetsWithTotalHeight:(CGFloat)totalHeight
{
	for (NSNumber *colHeight in _colOffsets) {
		totalHeight = (totalHeight < [colHeight floatValue]) ? [colHeight floatValue] : totalHeight;
	}
	return totalHeight;
}

- (void)relayoutViews {
    self.numCols = UIInterfaceOrientationIsPortrait(self.orientation) ? self.numColsPortrait : self.numColsLandscape;
    
    // Reset all state
    [self.visibleViews enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        PSCollectionViewCell *view = (PSCollectionViewCell *)obj;
        [self enqueueReusableView:view];
    }];
    [self.visibleViews removeAllObjects];
    [self.viewKeysToRemove removeAllObjects];
    [self.indexToRectMap removeAllObjects];
	if (_resetLoadedIndices) {
		self.loadedIndices = [NSMutableIndexSet indexSet];
		_resetLoadedIndices = NO;
	}
	
    if (self.emptyView) {
        [self.emptyView removeFromSuperview];
    }
    [self.loadingView removeFromSuperview];
    
    // This is where we should layout the entire grid first
    NSInteger numViews = [self.collectionViewDataSource numberOfViewsInCollectionView:self];
    
    CGFloat totalHeight = 0.0;
    CGFloat top = self.margin;
    
    // Add headerView if it exists
    if (self.headerView) {
        self.headerView.width = self.width;
		
        top = self.headerView.top;
        [self addSubview:self.headerView];
		
		CGSize headerSize = [self.headerView sizeThatFits:CGSizeMake(self.width, CGFLOAT_MAX)];
		self.headerView.height = headerSize.height;
		self.headerViewHeight = headerSize.height;
        top += self.headerView.height + self.margin;
    }
    
    if (numViews > 0) {
        // This array determines the last height offset on a column
        [self buildColumnOffsetsFromTop:top];
        
        // Calculate index to rect mapping
        self.colWidth = floorf((self.width - self.margin * (self.numCols + 1)) / self.numCols);
        for (NSInteger i = 0; i < numViews; i++) {
            PSCollectionViewKey *key = PSCollectionKeyForIndex(i);
            
            // Find the shortest column
            NSInteger col = [self findShortestColumn];
			[self insertViewRectForIndex:i forKey:key inColumn:col];
        }
		
		totalHeight = [self totalHeightFromColOffsetsWithTotalHeight:(CGFloat)totalHeight];
    } else {
        totalHeight = self.height;
        
        // If we have an empty view, show it
        if (self.emptyView) {
            self.emptyView.frame = CGRectMake(self.margin, top, self.width - self.margin * 2, self.height - top - self.margin);
            [self addSubview:self.emptyView];
        } else if (self.headerView) {
			totalHeight = top;
		} else {
			totalHeight = top;
		}
    }
    
    totalHeight = [self updateFooterViewWithTotalHeight:totalHeight];
    
    self.contentSize = CGSizeMake(self.width, totalHeight);
    
    [self removeAndAddCellsIfNecessary];
}

- (void)removeAndAddCellsIfNecessary {
    static NSInteger bufferViewFactor = 5;
    static NSInteger topIndex = 0;
    static NSInteger bottomIndex = 0;
    
    NSInteger numViews = [self.collectionViewDataSource numberOfViewsInCollectionView:self];
    if (numViews == 0) {
		return;
	}
    
    // Find out what rows are visible
    CGRect visibleRect = CGRectMake(self.contentOffset.x, self.contentOffset.y, self.width, self.height);
    
    // Remove all rows that are not inside the visible rect
    [self.visibleViews enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        PSCollectionViewCell *view = (PSCollectionViewCell *)obj;
        CGRect viewRect = view.frame;
        if (CGRectIntersectsRect(visibleRect, viewRect) == NO) {
            [self enqueueReusableView:view];
            [self.viewKeysToRemove addObject:key];
        }
    }];
    
    [self.visibleViews removeObjectsForKeys:self.viewKeysToRemove];
    [self.viewKeysToRemove removeAllObjects];
    
    if ([self.visibleViews count] == 0) {
        topIndex = 0;
        bottomIndex = numViews;
    } else {
		// need the highest and lowest values, so instead of an expensive sort, just iterate finding the high/low
		NSArray *allKeys = [self.visibleViews allKeys];
		topIndex = [(PSCollectionViewKey*)[allKeys objectAtIndex:0] key];
		bottomIndex = [(PSCollectionViewKey*)[allKeys objectAtIndex:0] key];
		[allKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			NSInteger value = [(PSCollectionViewKey*)obj key];
			if (value < topIndex) {
				topIndex = value;
			}
			if (value > bottomIndex) {
				bottomIndex = value;
			}
		}];
		
        topIndex = MAX(0, topIndex - (bufferViewFactor * self.numCols));
        bottomIndex = MIN(numViews, bottomIndex + (bufferViewFactor * self.numCols));
    }
    
    // Add views
    for (NSInteger i = topIndex; i < bottomIndex; i++) {
        PSCollectionViewKey *key = PSCollectionKeyForIndex(i);
		CGRect rect = [[self.indexToRectMap objectForKey:key] CGRectValue];
        
        // If view is within visible rect and is not already shown
        if (![self.visibleViews objectForKey:key] && CGRectIntersectsRect(visibleRect, rect)) {
            // Only add views if not visible
            PSCollectionViewCell *newView = [self.collectionViewDataSource collectionView:self viewAtIndex:i];
            newView.frame = [[self.indexToRectMap objectForKey:key] CGRectValue];
			if ([self.loadedIndices containsIndex:i]) {
				[self addSubview:newView];
			} else { //animate it in, add it to the set
				[self.loadedIndices addIndex:i];
				[self addSubview:newView];
				if (self.animateLayoutChanges) {
					newView.alpha = 0.0f;
					[UIView animateWithDuration:kAnimationDuration delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:^{
						newView.alpha = 1.0f;
					} completion:nil];
				}
			}
            
            [self.visibleViews setObject:newView forKey:key];
        }
    }
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
    PSCollectionViewCell *view = [self.reuseableViews anyObject];
    if (view) {
        // Found a reusable view, remove it from the set
        [self.reuseableViews removeObject:view];
    }
    return view;
}

- (void)enqueueReusableView:(PSCollectionViewCell *)view
{
	[view prepareForReuse];
    view.frame = CGRectZero;
	view.alpha = 1.0f;
    [self.reuseableViews addObject:view];
    [view removeFromSuperview];
}

#pragma mark - Gesture Recognizer

- (void)didSelectView:(UITapGestureRecognizer *)gestureRecognizer
{
	CGPoint tapPoint = [gestureRecognizer locationInView:self];
	
	//determine which grid item (if any) this tap was on
	PSCollectionViewCell *viewCell = nil;
	NSArray *visibleViewArray = [self.visibleViews allValues];
	for (PSCollectionViewCell *view in visibleViewArray) {
		if (CGRectContainsPoint(view.frame, tapPoint)) {
			viewCell = view;
			break;
		}
	}
	
	if (viewCell) {
		NSValue *rectValue = [NSValue valueWithCGRect:viewCell.frame];
		NSArray *matchingKeys = [self.indexToRectMap allKeysForObject:rectValue];
		PSCollectionViewKey *key = [matchingKeys lastObject];
		if ([viewCell isMemberOfClass:[[self.visibleViews objectForKey:key] class]]) {
			if (self.collectionViewDelegate && [self.collectionViewDelegate respondsToSelector:@selector(collectionView:didSelectView:atIndex:)]) {
				NSInteger matchingIndex = PSCollectionIndexForKey(key);
				[self.collectionViewDelegate collectionView:self didSelectView:viewCell atIndex:matchingIndex];
			}
		}
	}
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([gestureRecognizer isMemberOfClass:[PSCollectionViewTapGestureRecognizer class]] == NO) {
		return YES;
	}
    
    NSValue *rectValue = [NSValue valueWithCGRect:gestureRecognizer.view.frame];
    NSArray *matchingKeys = [self.indexToRectMap allKeysForObject:rectValue];
    NSString *key = [matchingKeys lastObject];
	return [touch.view isMemberOfClass:[[self.visibleViews objectForKey:key] class]];
}

@end
