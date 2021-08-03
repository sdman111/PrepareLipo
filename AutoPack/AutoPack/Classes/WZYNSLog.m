//
//  WZYNSLog.m
//  Pods-WZYTest_Tests
//
//  Created by 吴志颖 on 2021/8/2.
//

#import "WZYNSLog.h"

@implementation WZYNSLog

- (void)WZYNSLog {
    NSLog(@"WZYNSLog+++++++++++++++");
    [self performSelector:@selector(WZYCrash)];
}

- (void)WZYCrash {
    NSArray *arr = [[NSArray alloc] initWithObjects:@"abc" count:5];
    for (int i = 0; i < 10; i++) {
        printf("%d",arr[i]);
    }
    NSLog(@"here is a crash");
}

@end
