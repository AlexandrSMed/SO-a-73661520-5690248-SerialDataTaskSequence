//
//  TDWSerialDownloader.m
//  ObjCPlayground
//
//  Created by Aleksandr Medvedev on 09.09.2022.
//

#import <CFNetwork/CFHTTPStream.h>
#import "TDWSerialDataTaskSequence.h"

// Chunks requst timeout in seconds
static const NSTimeInterval kRequestTimeout = 60 * 4; // 4 minutes

typedef NS_ENUM(NSUInteger, TDWSerialDataTaskSequenceState) {
    TDWSerialDataTaskSequenceStateSuspended,
    TDWSerialDataTaskSequenceStateCancelled,
    TDWSerialDataTaskSequenceStateActive
};

@interface TDWSerialDataTaskSequence()<NSURLSessionDataDelegate>

@property(copy, nonatomic) NSArray<NSURL *> *urls;
@property(strong, readonly, nonatomic) NSURLSession *urlSession;
@property(strong, readonly, nonatomic) dispatch_queue_t progressAcessQueue;
@property(strong, readonly, nonatomic) NSOperationQueue *tasksQueue;
@property(strong, nonatomic) dispatch_semaphore_t taskSemaphore;

@property(strong, readonly, nonatomic) NSMutableData *data;
@property(copy, readonly, nonatomic) TDWSerialDataTaskSequenceCallback callback;
@property(assign, nonatomic) TDWSerialDataTaskSequenceState state;

@end

@implementation TDWSerialDataTaskSequence

@synthesize progress = _progress;

#pragma mark Lifecycle

- (instancetype)initWithURLArray:(NSArray<NSURL *> *)urls callback:(nullable TDWSerialDataTaskSequenceCallback)callback; {
    if (self = [super init]) {
        _urls = [[NSArray alloc] initWithArray:urls copyItems:NO];
        
        NSOperationQueue *queue = [NSOperationQueue new];
        queue.name = @"the.dreams.wind.queue.SerialDownloader";
        queue.maxConcurrentOperationCount = 1;
        _tasksQueue = queue;
        
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        _urlSession = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                    delegate:self
                                               delegateQueue:nil];
        
        _progress = [NSProgress progressWithTotalUnitCount:100];
        _progressAcessQueue = dispatch_queue_create("the.dreams.wind.queue.ProgressAcess", DISPATCH_QUEUE_CONCURRENT);
        _data = [NSMutableData data];
        _state = TDWSerialDataTaskSequenceStateSuspended;
        _callback = callback;
    }
    return self;
}

#pragma mark Actions

- (void)cancel {
    if (_state == TDWSerialDataTaskSequenceStateCancelled) {
        return;
    }
    [_urlSession invalidateAndCancel];
    [_tasksQueue cancelAllOperations];
    self.state = TDWSerialDataTaskSequenceStateCancelled;
}

- (void)resume {
    if (_state != TDWSerialDataTaskSequenceStateSuspended) {
        return;
    }
    
    _progress.completedUnitCount = 0;
    NSURLSession *session = _urlSession;
    // Prevents queue from starting the download straight away
    _tasksQueue.suspended = YES;
    
    // 3.1 Successful completion
    typeof(self) __weak weakSelf = self;
    NSOperation *lastOperation = [NSBlockOperation blockOperationWithBlock:^{
        if (!weakSelf) {
            return;
        }
        typeof(self) __strong strongSelf = weakSelf;
        
        strongSelf->_callback([strongSelf->_data copy], nil);
    }];
    [_tasksQueue addOperation:lastOperation];
    
    // 2. Data requests
    for (NSURL *url in _urls.reverseObjectEnumerator) {
        NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            if (!weakSelf) {
                return;
            }
            typeof(self) __strong strongSelf = weakSelf;
            NSLog(@"%@ started", url);
            strongSelf.taskSemaphore = dispatch_semaphore_create(0);
            NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url
                                                          cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                      timeoutInterval:kRequestTimeout];
            [[session dataTaskWithRequest:request] resume];
            dispatch_semaphore_wait(strongSelf->_taskSemaphore, DISPATCH_TIME_FOREVER);
            NSLog(@"%@ finished", url);
        }];
        if (lastOperation) {
            [lastOperation addDependency:operation];
        }
        lastOperation = operation;
        [_tasksQueue addOperation:operation];
    }
    
    // 1. Data length request
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        if (!weakSelf) {
            return;
        }
        
        typeof(weakSelf) __strong strongSelf = weakSelf;
        __block dispatch_group_t lengthRequestsGroup = dispatch_group_create();
        for (NSURL *url in strongSelf.urls) {
            dispatch_group_enter(lengthRequestsGroup);
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            request.HTTPMethod = @"HEAD";
            typeof(self) __weak weakSelf = strongSelf;
            NSURLSessionDataTask *task = [strongSelf->_urlSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
                if (!weakSelf) {
                    return;
                }
                typeof(weakSelf) __strong strongSelf = weakSelf;
                [strongSelf p_changeProgressSynchronised:^(NSProgress *progress) {
                    progress.totalUnitCount += response.expectedContentLength;
                    NSLog(@"Recieved for %@: %lld", response.URL, response.expectedContentLength);
                    dispatch_group_leave(lengthRequestsGroup);
                }];
            }];
            [task resume];
        }
        dispatch_group_wait(lengthRequestsGroup, DISPATCH_TIME_FOREVER);
        NSLog(@"Length recieved: %lld", strongSelf.progress.totalUnitCount);
    }];
    [lastOperation addDependency:operation];
    [_tasksQueue addOperation:operation];
    _tasksQueue.suspended = NO;
    self.state = TDWSerialDataTaskSequenceStateActive;
}

#pragma mark Properties

- (NSProgress *)progress {
    __block NSProgress *localProgress;
    dispatch_sync(_progressAcessQueue, ^{
        localProgress = _progress;
    });
    return localProgress;
}

- (void)p_changeProgressSynchronised:(void (^)(NSProgress *))progressChangeBlock {
    typeof(self) __weak weakSelf = self;
    dispatch_barrier_async(_progressAcessQueue, ^{
        if (!weakSelf) {
            return;
        }
        typeof(weakSelf) __strong strongSelf = weakSelf;
        progressChangeBlock(strongSelf->_progress);
    });
}

#pragma mark NSURLSessionDataDelegate


- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self cancel];
        // 3.2 Failed completion
        _callback([_data copy], error);
    }
    dispatch_semaphore_signal(_taskSemaphore);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // read/append data if needed
    [_data appendData:data];
    [self p_changeProgressSynchronised:^(NSProgress *progress) {
        progress.completedUnitCount += data.length;
    }];
}


@end
