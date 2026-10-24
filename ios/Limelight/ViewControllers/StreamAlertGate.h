//
//  StreamAlertGate.h
//  Starwire
//
//  Decides whether a stream error may show an alert. One failure often reports itself twice
//  (a stage failure, then the connection terminating), and iOS refuses to present a second alert
//  over the first ("already presenting"). The first alert of a stream is shown; later ones are
//  only logged, and nothing is shown once the stream screen is closing.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StreamAlertGate : NSObject

// The stream screen is closing: no more alerts
- (void)markExiting;
@property (nonatomic, readonly) BOOL exiting;

// YES the first time for a stream, while not exiting. Otherwise NO, and the title is recorded.
- (BOOL)shouldPresentAlertWithTitle:(NSString *)title;

// Titles of alerts that were not shown, oldest first
@property (nonatomic, readonly) NSArray<NSString *> *suppressedTitles;

@end

NS_ASSUME_NONNULL_END
