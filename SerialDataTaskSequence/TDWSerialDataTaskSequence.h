//
//  TDWSerialDownloader.h
//  ObjCPlayground
//
//  Created by Aleksandr Medvedev on 09.09.2022.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

typedef void(^TDWSerialDataTaskSequenceCallback)(NSData *data, NSError *_Nullable error);

@interface TDWSerialDataTaskSequence : NSObject

@property(copy, readonly, nonatomic) NSArray<NSURL *> *urls;
@property(strong, readonly, nonatomic) NSProgress *progress;

- (instancetype)initWithURLArray:(NSArray<NSURL *> *)urls callback:(nullable TDWSerialDataTaskSequenceCallback)callback;
- (void)resume;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
