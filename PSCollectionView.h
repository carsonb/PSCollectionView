//
// PSCollectionView.h
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

#import <UIKit/UIKit.h>

@class PSCollectionViewCell;

@protocol PSCollectionViewDelegate, PSCollectionViewDataSource;

@interface PSCollectionView : UIScrollView

#pragma mark - Public Properties

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *footerView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIView *loadingView;

@property (nonatomic, assign, readwrite) CGFloat margin;
@property (nonatomic, assign, readonly) CGFloat colWidth;
@property (nonatomic, assign, readonly) NSInteger numCols;
@property (nonatomic, assign) NSInteger numColsLandscape;
@property (nonatomic, assign) NSInteger numColsPortrait;
@property (nonatomic, assign) BOOL animateLayoutChanges;
@property (nonatomic, weak) id <PSCollectionViewDelegate> collectionViewDelegate;
@property (nonatomic, weak) id <PSCollectionViewDataSource> collectionViewDataSource;

#pragma mark - Public Methods

- (void)invalidateLayout;

/**
 Reloads the collection view
 This is similar to UITableView reloadData)
 */
- (void)reloadData;

/**
 Dequeues a reusable view that was previously initialized
 This is similar to UITableView dequeueReusableCellWithIdentifier
 */
- (PSCollectionViewCell *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier;

- (void)insertItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)removeItemAtIndexPath:(NSIndexPath *)indexPath;

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(void))completion;

@end

#pragma mark - Delegate

@protocol PSCollectionViewDelegate <NSObject>

@optional
- (void)collectionView:(PSCollectionView *)collectionView didSelectView:(PSCollectionViewCell *)view atIndexPath:(NSIndexPath *)indexPath;

@end

#pragma mark - DataSource

@protocol PSCollectionViewDataSource <NSObject>

@required
- (NSUInteger)numberOfSectionsInCollectionView:(PSCollectionView *)collectionView;
- (NSUInteger)collectionView:(PSCollectionView *)collectionView numberOfViewsInSection:(NSUInteger)section;
- (PSCollectionViewCell *)collectionView:(PSCollectionView *)collectionView viewAtIndexPath:(NSIndexPath *)indexPath;
- (CGFloat)collectionView:(PSCollectionView *)collectionView heightForViewAtIndexPath:(NSIndexPath *)indexPath;

@optional
- (UIView *)collectionView:(PSCollectionView *)collectionView sectionHeaderForSection:(NSUInteger)section;

@end
