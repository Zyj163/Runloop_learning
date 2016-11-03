//
//  TestViewController.m
//  runloop学习
//
//  Created by ddn on 16/9/1.
//  Copyright © 2016年 ddn. All rights reserved.
//

//CFRunLoop不返回
/*
 创建之后
 1    kCFRunLoopEntry
 2    kCFRunLoopBeforeTimers
 4    kCFRunLoopBeforeSources
 32   kCFRunLoopBeforeWaiting
 
 唤醒后
 64   kCFRunLoopAfterWaiting
 2    kCFRunLoopBeforeTimers
 4    kCFRunLoopBeforeSources
 处理被single的source
 _perform.......
 2    kCFRunLoopBeforeTimers
 4    kCFRunLoopBeforeSources
 32   kCFRunLoopBeforeWaiting
 */


//CFRunLoop返回，不可以再次唤醒
/*
 创建之后
 1    kCFRunLoopEntry
 2    kCFRunLoopBeforeTimers
 4    kCFRunLoopBeforeSources
 32   kCFRunLoopBeforeWaiting
 
 唤醒后
 64   kCFRunLoopAfterWaiting
 2    kCFRunLoopBeforeTimers
 4    kCFRunLoopBeforeSources
 处理被single的source
 _perform.......
 128  kCFRunLoopExit
 */

#import "TestViewController.h"

@implementation TestViewController
{
    NSThread *thread;
    CFRunLoopSourceRef source;
    CFRunLoopRef runloop;
}

static void _perform(void *info) {
    printf("_perform....... %p\n",info);
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    thread = [[NSThread alloc]initWithTarget:self selector:@selector(subThread) object:nil];
    [thread start];
}

- (void)subThread
{
    runloop = CFRunLoopGetCurrent();
    
    CFRunLoopSourceContext ctx = {
        .version = 0,
        .info = (__bridge void *)self,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        .perform = _perform
    };
    
    source = CFRunLoopSourceCreate(nil, 0, &ctx);
    
    //只能有一个source，添加之前先移除之前的（如果有）
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities, true, -1, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        printf("%lu\n", activity);
    });
    
    CFRunLoopAddObserver(runloop, observer, kCFRunLoopDefaultMode);
    
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, false);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    //先标记好要处理的source
    CFRunLoopSourceSignal(source);
    //唤醒后回去处理被标记的source
    CFRunLoopWakeUp(runloop);
}

@end
