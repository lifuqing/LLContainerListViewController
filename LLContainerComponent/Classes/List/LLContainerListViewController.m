//
//  LLContainerListViewController.m
//  LLContainerComponent
//
//  Created by lifuqing on 2018/9/13.
//

#import "LLContainerListViewController.h"
#import <LLHttpEngine/LLListBaseDataSource.h>
#import "LLLoadingView.h"
#import "LLBaseTableViewCell.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "NSObject+LLTools.h"

@interface LLContainerListViewController () <LLListBaseDataSourceDelegate, UITableViewDelegate, UITableViewDataSource>

#pragma mark - request
///列表刷新方式
@property (nonatomic, assign) ListRefreshType refreshType;
///列表数据清除方式
@property (nonatomic, assign) ListClearType clearType;
///使用默认错误提示，默认YES
@property (nonatomic, assign) BOOL enableNetworkError;
///使用没有更多啦封底，默认NO
@property (nonatomic, assign) BOOL enableTableBottomView;
///是否支持预加载更多数据，默认NO
@property (nonatomic, assign) BOOL enablePreLoad;
///loading
@property (nonatomic, strong) LLLoadingView *loadingView;


#pragma mark - 列表相关
@property (nonatomic, strong, readwrite) UITableView *listTableView;
@property (nonatomic, strong, readwrite) LLListBaseDataSource *listDataSource;
@property (nonatomic, strong, readwrite) NSMutableArray *listArray;

@end

@interface LLContainerListViewController(Expose)

#pragma mark - 曝光相关
- (void)exposeStatistics;
@end

@implementation LLContainerListViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self commitInit];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.edgesForExtendedLayout = UIRectEdgeNone;//view的底部是tabbar的顶部，不会被覆盖一部分
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    self.view.clipsToBounds = YES;
    
    [self.view addSubview:self.listTableView];
    
    [self extraConfigTableView];
    
    self.refreshType = ListRefreshTypeLoadingView | ListRefreshTypePullToRefresh;
}

- (void)dealloc {
    _listTableView.delegate = nil;
    _listTableView.dataSource = nil;
}

#pragma mark - 初始化
- (void)commitInit {
    _enableNetworkError = YES;
    _clearType = ListClearTypeAfterRequest;
    
    _listArray = [NSMutableArray array];
}

#pragma mark - 数据获取
///请求全部数据，包括筛选条件和列表，默认不忽略中间loading
- (void)requestData {
    [self requestDataIgnoreCenterLoading:NO];
}
///请求全部数据，包括筛选条件和列表ignore 是否忽略中间loading
- (void)requestDataIgnoreCenterLoading:(BOOL)ignore {
    [self requestDataWillStartIgnoreCenterLoading:ignore];
    
    ///请求列表
    [self requestListData];
}

///列表请求将开始
- (void)requestDataWillStartIgnoreCenterLoading:(BOOL)ignore {
    //清空数据源
    if (_clearType == ListClearTypeBeforeRequest) { //请求前清除数据源
        if (_listArray.count > 0) {
            [_listArray removeAllObjects];
            [_listTableView reloadData];
        }
    }
    
    //显示加载视图
    if (_refreshType & ListRefreshTypeLoadingView && !ignore) {
        if (!_loadingView) {
            _loadingView = [[LLLoadingView alloc] initWithFrame:CGRectMake(0.0, 0.0, 300.0, 300.0)]; //给定足够大的尺寸
            _loadingView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        }
        _loadingView.center = CGPointMake(self.view.frame.size.width / 2.0, self.view.frame.size.height / 2.0);
        [self.view addSubview:_loadingView];
        [_loadingView startAnimating];
    }
    
    if (_enableNetworkError) {
        [self hideErrorView];
    }
}

///请求列表数据
- (void)requestListData {
    NSDictionary *param = nil;
    [self.listDataSource resetParams];
    if ([_listDelegate respondsToSelector:@selector(requestListPargamsForListController:)]) {
        param = [_listDelegate requestListPargamsForListController:self];
    }
    [self.listDataSource.llurl.params addEntriesFromDictionary:param];
    
    if ([_listDelegate respondsToSelector:@selector(requestListCacheTypeForListController:)]) {
        self.listDataSource.llurl.cacheType = [_listDelegate requestListCacheTypeForListController:self];
    }
    
    [self.listDataSource load];
}

///请求更多列表数据
- (void)requestMoreListData {
    if (_listDataSource.hasMore) {
        [self.listDataSource loadMore];
    }
    else {
        if (self.enableTableBottomView) {
            [_listTableView.pullToLoadMoreView stopAnimatingWithNoMoreData];
        }
        else {
            //需要放到[_listTableView.pullToLoadMoreView stopAnimating];之前，否则状态会错
            if (self.listTableView.pullToLoadMoreView.previousState != YLPullToLoadMoreStatePreLoadTriggered) {
                [self showMessage:@"没有更多数据啦~" inView:self.view];
                //如果没有更多数据的时候不支持上拉了就加上下面这句话，但是给用户的感知是不知道没有更多啦。请先不要删除
//                // 与|=配对，比较靠谱 用^=有风险 0^=1就有问题了
//                self.refreshType &= ~ListRefreshTypeInfiniteScrolling;
            }
            [_listTableView.pullToLoadMoreView stopAnimating];
        }
    }
}

///请求完成后的处理
- (void)handleRequestFinish {
    if (self.listDataSource.error) {
        if (self.refreshType & ListRefreshTypeInfiniteScrolling) {
            // 与|=配对，比较靠谱 用^=有风险 0^=1就有问题了
            self.refreshType &= ~ListRefreshTypeInfiniteScrolling;
        }
        [self requestListDataFailedWithError:[NSError errorWithDomain:self.listDataSource.error.domain code:ListErrorCodeFailed userInfo:nil] requestType:self.listDataSource.llurl.curRequestType];
    }
    else {
        if (self.listDataSource.list.count > 0) {
            if (self.listDataSource.hasMore) {
                if (!(self.refreshType & ListRefreshTypeInfiniteScrolling)) {
                    self.refreshType |= ListRefreshTypeInfiniteScrolling;
                }
            }
            else {
                if (self.listDataSource.llurl.curRequestType == LLRequestTypeRefresh) {
                    if (self.refreshType & ListRefreshTypeInfiniteScrolling) {
                        // 与|=配对，比较靠谱 用^=有风险 0^=1就有问题了
                        self.refreshType &= ~ListRefreshTypeInfiniteScrolling;
                    }
                }
            }
        }
        else {
            if (self.refreshType & ListRefreshTypeInfiniteScrolling) {
                // 与|=配对，比较靠谱 用^=有风险 0^=1就有问题了
                self.refreshType &= ~ListRefreshTypeInfiniteScrolling;
            }
        }
        [self requestListDataSuccessWithArray:self.listDataSource.list];
    }
    
    [self refreshLayoutViews];
    //曝光
    [self exposeStatistics];
}

///创建之后外部需要额外设置属性的时候调用
- (void)extraConfigTableView {
    
}

///刷新视图frame
- (void)refreshLayoutViews {
    _listTableView.frame = CGRectMake(0, 0, CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame));
}

///请求列表成功
- (void)requestListDataSuccessWithArray:(NSArray *)array {
    [self endRefresh];
    
    if (_listArray.count
        && array.count
        && [_listArray isEqualToArray:array]) { //数据未变更
        return;
    }
    
    self.listArray.array = array;
    
    [_listTableView reloadData];
    
    //隐藏错误提示
    if (_enableNetworkError) {
        [self hideErrorView];
        if (array.count == 0) {
            [self showErrorViewWithErrorType:LLErrorTypeNoData selector:@selector(touchErrorViewAction)];
        }
    }
    
}

///请求列表失败
- (void)requestListDataFailedWithError:(NSError *)error {
    //清空数据源
    if (_clearType == ListClearTypeAfterRequest) {
        [_listArray removeAllObjects];
        [_listTableView reloadData];
    }

    [self endRefresh];
    
    //显示错误提示视图
    if (_enableNetworkError) {
        if (error.code == ListErrorCodeFailed) { //数据错误
            [self showErrorViewWithErrorType:LLErrorTypeFailed selector:@selector(touchErrorViewAction)];
            [self showMessage:error.domain inView:self.view];
        } else if (error.code == ListErrorCodeNetwork) { //网络错误
            [self showErrorViewWithErrorType:LLErrorTypeNoNetwork selector:@selector(touchErrorViewAction)];
            [self showMessage:error.domain inView:self.view];
        }
    }
}

///请求列表失败,包括下拉刷新和加载更多
- (void)requestListDataFailedWithError:(NSError *)error requestType:(LLRequestType)requestType {
    if (requestType == LLRequestTypeRefresh) {
        [self requestListDataFailedWithError:error];
    }
    else {
        //显示错误提示视图，previousState的使用需要放到endRefresh之前
        if (_enableNetworkError && self.listTableView.pullToLoadMoreView.previousState != YLPullToLoadMoreStatePreLoadTriggered) {
            if (error.code == ListErrorCodeFailed) { //数据错误
                [self showMessage:error.domain inView:self.view];
            } else if (error.code == ListErrorCodeNetwork) { //网络错误
                [self showMessage:error.domain inView:self.view];
            }
        }
        [self endRefresh];
    }
}

#pragma mark - HUD
- (void)showMessage:(NSString *)message inView:(UIView *)view {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:view animated:YES];
    hud.mode = MBProgressHUDModeText;
    hud.label.text = message;
    hud.userInteractionEnabled = NO;
    [hud hideAnimated:YES afterDelay:1];
}

#pragma mark - Error View
//默认点击提示信息事件
- (void)touchErrorViewAction
{
    if (_refreshType & ListRefreshTypeLoadingView) {
        [self requestData];
    } else if (_refreshType & ListRefreshTypePullToRefresh) {
        if (_enableNetworkError) {
            [self hideErrorView];
        }
        [_listTableView triggerPullToRefresh];
    } else {
        [self requestData];
    }
}

- (void)hideErrorView {
    [LLErrorView hideErrorViewInView:self.listTableView];
}

- (void)showErrorViewWithErrorType:(LLErrorType)errorType selector:(SEL)selector {
    BOOL shouldShowError = YES;
    if ([_listDelegate respondsToSelector:@selector(shouldShowErrorViewAndToastForListController:)]) {
        shouldShowError = [_listDelegate shouldShowErrorViewAndToastForListController:self];
    }
    if (shouldShowError && self.listDataSource.type == LLRequestTypeRefresh) {
        __weak __typeof(self) weakSelf = self;
        [LLErrorView showErrorViewInView:self.listTableView withErrorType:errorType withClickBlock:^{
            IMP imp = [weakSelf methodForSelector:selector];
            void (*func)(id, SEL) = (void *)imp;
            func(weakSelf, selector);
        }];
    }
}


///请求之后结束刷新状态
- (void)endRefresh {
    //隐藏加载视图
    if (_refreshType & ListRefreshTypeLoadingView) { //中心加载视图
        [_loadingView stopAnimating];
        [_loadingView removeFromSuperview];
    }
    
    if (_refreshType & ListRefreshTypePullToRefresh && _listTableView.pullToRefreshView.state == YLPullToRefreshStateLoading) { //下拉刷新
        [_listTableView.pullToRefreshView stopAnimating];
    }
    
    if (_refreshType & ListRefreshTypeInfiniteScrolling && _listTableView.pullToLoadMoreView.state == YLPullToLoadMoreStateLoading) { //上拉加载更多
        if (self.listDataSource.hasMore) {
            [_listTableView.pullToLoadMoreView stopAnimating];
        }
        else {
            if (self.enableTableBottomView) {
                [_listTableView.pullToLoadMoreView stopAnimatingWithNoMoreData];
            }
            else {
                [_listTableView.pullToLoadMoreView stopAnimating];
            }
        }
    }
}


#pragma mark - Property & setter

- (void)setRefreshType:(ListRefreshType)refreshType
{
    if (_refreshType != refreshType) {
        _refreshType = refreshType;
        //注意，很有可能在viewdidload之前调用，所以不要轻易使用lazyloading 创建tableview
        __weak typeof(self) weakSelf = self;
        //下拉刷新
        if (self.isViewLoaded) {
            if (refreshType & ListRefreshTypePullToRefresh) {
                [self.listTableView addPullToRefreshWithActionHandler:^{
                    [weakSelf requestDataIgnoreCenterLoading:YES];
                    if ([weakSelf.eventDelegate respondsToSelector:@selector(eventPullRefreshForListController:)]) {
                        [weakSelf.eventDelegate eventPullRefreshForListController:weakSelf];
                    }
                }];
            }
            else {
                _listTableView.showsPullToRefresh = NO;
            }
        } else {
            [_listTableView.pullToRefreshView stopAnimating];
        }
        
        //上拉加载更多
        if (self.isViewLoaded) {
            if (refreshType & ListRefreshTypeInfiniteScrolling) {
                [self.listTableView addPullToLoadMoreWithActionHandler:^{
                    [weakSelf requestMoreListData];
                }];
                _listTableView.showsPullToLoadMore = YES;
                _listTableView.pullToLoadMoreView.preLoad = self.enablePreLoad;
            } else {
                _listTableView.showsPullToLoadMore = NO;
            }
        } else {
            [_listTableView.pullToLoadMoreView stopAnimating];
        }
    }
}

#pragma mark - Property & getter
- (LLListBaseDataSource *)listDataSource {
	if (!_listDataSource)
	{
        NSString *listParser = nil;
        if ([_listDelegate respondsToSelector:@selector(requestListParserForListController:)])
        {
            listParser = [_listDelegate requestListParserForListController:self];
        }
        
        Class listConfigClass = nil;
        if ([_listDelegate respondsToSelector:@selector(requestListURLConfigClassForListController:)])
        {
            listConfigClass = [_listDelegate requestListURLConfigClassForListController:self];
        }
        
        Class dataSourceClass = [LLListBaseDataSource class];
        if ([_listDelegate respondsToSelector:@selector(requestListDataSourceClassForListController:)])
        {
            dataSourceClass = [_listDelegate requestListDataSourceClassForListController:self];
        }
        
		_listDataSource = [[dataSourceClass alloc] initWithDelegate:self parser:listParser urlConfigClass:listConfigClass];
        
	}
	return _listDataSource;
}

- (UITableView *)listTableView {
    if (!_listTableView) {
        _listTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _listTableView.dataSource = self;
        _listTableView.delegate = self;
        _listTableView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        _listTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        
        _listTableView.frame = CGRectMake(0, 0, CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame));
        
        if (@available(iOS 11, *)) {
            _listTableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
            _listTableView.estimatedRowHeight = 0;
            _listTableView.estimatedSectionHeaderHeight = 0;
            _listTableView.estimatedSectionFooterHeight = 0;
        }
    }
    return _listTableView;
}

#pragma mark - LLListBaseDataSourceDelegate
- (void)finishOfDataSource:(LLListBaseDataSource *)dataSource {
    [self handleRequestFinish];
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([_listDelegate respondsToSelector:@selector(listController:rowCountInSection:)]) {
        return [_listDelegate listController:self rowCountInSection:section];
    }
    return _listArray.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([_listDelegate respondsToSelector:@selector(listController:sectionCountInTableView:)]) {
        return [_listDelegate listController:self sectionCountInTableView:tableView];
    }
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([_listDelegate respondsToSelector:@selector(listController:rowHeightAtIndexPath:)]) {
        return [_listDelegate listController:self rowHeightAtIndexPath:indexPath];
    }
    return 0;
}

- (nonnull UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    //复用参数
    Class class = nil;
    NSString *identifier = nil;
    
    if ([_listDelegate respondsToSelector:@selector(listController:cellClassAtIndexPath:)]) {
        class = [_listDelegate listController:self cellClassAtIndexPath:indexPath];
    }
    if ([_listDelegate respondsToSelector:@selector(listController:cellIdentifierAtIndexPath:)]) {
        identifier = [_listDelegate listController:self cellIdentifierAtIndexPath:indexPath];
    }
    if (!class) {
        class = [UITableViewCell class];
    }
    if (!identifier.length) {
        identifier = [NSString stringWithFormat:@"%@", NSStringFromClass(class)]; //同类卡片内部复用cell
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[class alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.clipsToBounds = YES;
        cell.exclusiveTouch = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    if ([_listDelegate respondsToSelector:@selector(listController:reuseCell:atIndexPath:)]) {
        [_listDelegate listController:self reuseCell:cell atIndexPath:indexPath];
    }
    
    return cell;
}


#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([_listDelegate respondsToSelector:@selector(listController:didSelectedCellAtIndexPath:)]) {
        [_listDelegate listController:self didSelectedCellAtIndexPath:indexPath];
    }
    
    if ([_eventDelegate respondsToSelector:@selector(eventListController:clickDidSelectedCellAtIndexPath:)]) {
        [_eventDelegate eventListController:self clickDidSelectedCellAtIndexPath:indexPath];
    }
}

@end

#pragma mark - 曝光 Expose

@implementation LLContainerListViewController (Expose)

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) {
        //发送曝光埋点
        [self exposeStatistics];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    //发送曝光埋点
    [self exposeStatistics];
}

///曝光埋点
- (void)exposeStatistics
{
    if (!self.exposeDelegate) return;
    
    NSMutableArray<NSIndexPath *> *exposeArray = [NSMutableArray array];
    
    NSArray<UITableViewCell *> *visibleCellArray = [self.listTableView visibleCells];
    
    [visibleCellArray enumerateObjectsUsingBlock:^(UITableViewCell * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSIndexPath *indexPath = [self.listTableView indexPathForCell:obj];
        if (CGRectContainsRect([self exposeFrame], obj.frame)) {//没有完全展示,直接跳过
            BOOL should = YES;
            if ([self.exposeDelegate respondsToSelector:@selector(exposeShouldExposeAtIndexPath:forListController:)]) {
                should = [self.exposeDelegate exposeShouldExposeAtIndexPath:indexPath forListController:self];
            }
            
            if (should) {
                [exposeArray addObject:indexPath];
            }
        }
    }];
    
    if (exposeArray.count > 0) {
        /// 数据设置曝光
        NSArray *exposeDataArray = nil;
        if ([self.exposeDelegate respondsToSelector:@selector(exposeListParseExposeArrayWithIndexPath:)]) {
            exposeDataArray = [self.exposeDelegate exposeListParseExposeArrayWithIndexPath:exposeArray];
        }
        else {
            exposeDataArray = [self parseExposeArrayWithIndexPath:exposeArray];
        }
        
        if (exposeDataArray.count > 0 && [self.exposeDelegate respondsToSelector:@selector(exposeListSendExposeStatisticsWithData:)]) {
            [self.exposeDelegate exposeListSendExposeStatisticsWithData:exposeDataArray];
        }
    }
}

///根据indexpath解析曝光数据源，遍历之后将数据源LLBaseResponseModel类型的属性ll_exposed设置为YES
- (nullable NSArray *)parseExposeArrayWithIndexPath:(nullable NSArray<NSIndexPath *> *)exposeArray {
    
    __block NSMutableArray <LLBaseResponseModel *> *exposeDataArray = [NSMutableArray array];
    
    [exposeArray enumerateObjectsUsingBlock:^(NSIndexPath * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        LLBaseTableViewCell *cell = [self.listTableView cellForRowAtIndexPath:obj];
        if ([cell isKindOfClass:[LLBaseTableViewCell class]]) {
            LLBaseResponseModel *model = cell.model;
            if (model && !model.ll_exposed) {
                model.ll_exposed = YES;
                [exposeDataArray addObject:model];
            }
        }
    }];
    return [exposeDataArray copy];
}


- (CGRect)exposeFrame
{
    CGFloat bottomInset = self.listTableView.contentInset.bottom;
    if (self.refreshType & ListRefreshTypeInfiniteScrolling) { //已设置加载更多控件
        bottomInset = self.listTableView.pullToLoadMoreView.originalBottomInset;
    }
    return CGRectMake(0, self.listTableView.contentOffset.y + self.listTableView.contentInset.top, self.listTableView.frame.size.width, self.listTableView.frame.size.height - self.listTableView.contentInset.top - bottomInset);
}
@end
