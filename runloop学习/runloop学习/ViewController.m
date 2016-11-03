//
//  ViewController.m
//  runloop学习
//
//  Created by ddn on 16/7/14.
//  Copyright © 2016年 ddn. All rights reserved.
//

/*
 AutoreleasePool
 
 App启动后，苹果在主线程 RunLoop 里注册了两个 Observer，其回调都是 _wrapRunLoopWithAutoreleasePoolHandler()。
 
 第一个 Observer 监视的事件是 Entry(即将进入Loop)，其回调内会调用 _objc_autoreleasePoolPush() 创建自动释放池。其 order 是-2147483647，优先级最高，保证创建释放池发生在其他所有回调之前。
 
 第二个 Observer 监视了两个事件： BeforeWaiting(准备进入休眠) 时调用_objc_autoreleasePoolPop() 和 _objc_autoreleasePoolPush() 释放旧的池并创建新池；Exit(即将退出Loop) 时调用 _objc_autoreleasePoolPop() 来释放自动释放池。这个 Observer 的 order 是 2147483647，优先级最低，保证其释放池子发生在其他所有回调之后。
 
 在主线程执行的代码，通常是写在诸如事件回调、Timer回调内的。这些回调会被 RunLoop 创建好的 AutoreleasePool 环绕着，所以不会出现内存泄漏，开发者也不必显示创建 Pool 了。
 
 
 
 事件响应
 
 苹果注册了一个 Source1 (基于 mach port 的) 用来接收系统事件，其回调函数为 __IOHIDEventSystemClientQueueCallback()。
 
 当一个硬件事件(触摸/锁屏/摇晃等)发生后，首先由 IOKit.framework 生成一个 IOHIDEvent 事件并由 SpringBoard 接收。这个过程的详细情况可以参考这里。SpringBoard 只接收按键(锁屏/静音等)，触摸，加速，接近传感器等几种 Event，随后用 mach port 转发给需要的App进程。随后苹果注册的那个 Source1 就会触发回调，并调用 _UIApplicationHandleEventQueue() 进行应用内部的分发。
 
 _UIApplicationHandleEventQueue() 会把 IOHIDEvent 处理并包装成 UIEvent 进行处理或分发，其中包括识别 UIGesture/处理屏幕旋转/发送给 UIWindow 等。通常事件比如 UIButton 点击、touchesBegin/Move/End/Cancel 事件都是在这个回调中完成的。
 
 
 
 手势识别
 
 当上面的 _UIApplicationHandleEventQueue() 识别了一个手势时，其首先会调用 Cancel 将当前的 touchesBegin/Move/End 系列回调打断。随后系统将对应的 UIGestureRecognizer 标记为待处理。
 
 苹果注册了一个 Observer 监测 BeforeWaiting (Loop即将进入休眠) 事件，这个Observer的回调函数是 _UIGestureRecognizerUpdateObserver()，其内部会获取所有刚被标记为待处理的 GestureRecognizer，并执行GestureRecognizer的回调。
 
 当有 UIGestureRecognizer 的变化(创建/销毁/状态改变)时，这个回调都会进行相应处理。
 
 
 
 
 
 界面更新
 
 当在操作 UI 时，比如改变了 Frame、更新了 UIView/CALayer 的层次时，或者手动调用了 UIView/CALayer 的 setNeedsLayout/setNeedsDisplay方法后，这个 UIView/CALayer 就被标记为待处理，并被提交到一个全局的容器去。
 
 苹果注册了一个 Observer 监听 BeforeWaiting(即将进入休眠) 和 Exit (即将退出Loop) 事件，回调去执行一个很长的函数：
 
 _ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv()。这个函数里会遍历所有待处理的 UIView/CAlayer 以执行实际的绘制和调整，并更新 UI 界面。
 
 
 
 
 
 定时器
 
 NSTimer 其实就是 CFRunLoopTimerRef，他们之间是 toll-free bridged 的。一个 NSTimer 注册到 RunLoop 后，RunLoop 会为其重复的时间点注册好事件。例如 10:00, 10:10, 10:20 这几个时间点。RunLoop为了节省资源，并不会在非常准确的时间点回调这个Timer。Timer 有个属性叫做 Tolerance (宽容度)，标示了当时间点到后，容许有多少最大误差。
 
 如果某个时间点被错过了，例如执行了一个很长的任务，则那个时间点的回调也会跳过去，不会延后执行。就比如等公交，如果 10:10 时我忙着玩手机错过了那个点的公交，那我只能等 10:20 这一趟了。
 
 
 
 
 
 PerformSelecter
 
 当调用 NSObject 的 performSelecter:afterDelay: 后，实际上其内部会创建一个 Timer 并添加到当前线程的 RunLoop 中。所以如果当前线程没有 RunLoop，则这个方法会失效。
 
 当调用 performSelector:onThread: 时，实际上其会创建一个 Timer 加到对应的线程去，同样的，如果对应线程没有 RunLoop 该方法也会失效。
 
 
 
 
 关于GCD
 
 实际上 RunLoop 底层也会用到 GCD 的东西，比如 RunLoop 是用 dispatch_source_t 实现的 Timer。但同时 GCD 提供的某些接口也用到了 RunLoop， 例如 dispatch_async()。
 
 当调用 dispatch_async(dispatch_get_main_queue(), block) 时，libDispatch 会向主线程的 RunLoop 发送消息，RunLoop会被唤醒，并从消息中取得这个 block，并在回调 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__() 里执行这个 block。但这个逻辑仅限于 dispatch 到主线程，dispatch 到其他线程仍然是由 libDispatch 处理的。
 */


#import "ViewController.h"
//#include <IOKit/hid/IOHIDEventSystem.h>
//#include <stdio.h>

@interface ViewController ()

//{
//    id observer;
//}

{
    UIScrollView *scrollView;
    
    BOOL cancel;
    
    NSRunLoop *runloop;
}

@end

@implementation ViewController

static CFDataRef Callback(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {
    NSLog(@"Callback..........%@",info);
    return nil;
}

static void NotifyCallback(CFNotificationCenterRef center,
                     void *observer,
                     CFStringRef name,
                     const void *object,
                     CFDictionaryRef userInfo)
{
    NSLog(@"NotifyCallback..........%@", userInfo);
}

void ObserverCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    NSLog(@"ObserverCallback...........%@",info);
}

static void _perform(void *info) {
    printf("_perform....... %p",info);
}

static void _timer(CFRunLoopTimerRef timer __unused, void *info) {
    CFRunLoopSourceSignal(info);
}

//void handle_event (void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event) {
//    // handle the events here.
//    printf("Received event of type %2d from service %p.\n", IOHIDEventGetType(event), service);
//}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //        CFRunLoopGetMain()
    //        CFRunLoopGetCurrent()
    
    //        CFRunLoopAddCommonMode(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##mode: CFString!##CFString!#>)
    
    
    //        CFRunLoopAddSource(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##source: CFRunLoopSource!##CFRunLoopSource!#>, <#T##mode: CFString!##CFString!#>)
    
    
    //        typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    //            kCFRunLoopEntry         = (1UL << 0), // 即将进入Loop
    //            kCFRunLoopBeforeTimers  = (1UL << 1), // 即将处理 Timer
    //            kCFRunLoopBeforeSources = (1UL << 2), // 即将处理 Source
    //            kCFRunLoopBeforeWaiting = (1UL << 5), // 即将进入休眠
    //            kCFRunLoopAfterWaiting  = (1UL << 6), // 刚从休眠中唤醒
    //            kCFRunLoopExit          = (1UL << 7), // 即将退出Loop
    //        };
    
    //        CFRunLoopAddObserver(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##observer: CFRunLoopObserver!##CFRunLoopObserver!#>, <#T##mode: CFString!##CFString!#>)
    //        CFRunLoopAddTimer(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##timer: CFRunLoopTimer!##CFRunLoopTimer!#>, <#T##mode: CFString!##CFString!#>)
    //        CFRunLoopRemoveSource(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##source: CFRunLoopSource!##CFRunLoopSource!#>, <#T##mode: CFString!##CFString!#>)
    //        CFRunLoopRemoveObserver(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##observer: CFRunLoopObserver!##CFRunLoopObserver!#>, <#T##mode: CFString!##CFString!#>)
    //        CFRunLoopAddTimer(<#T##rl: CFRunLoop!##CFRunLoop!#>, <#T##timer: CFRunLoopTimer!##CFRunLoopTimer!#>, <#T##mode: CFString!##CFString!#>)
    
    /**
     *  用DefaultMode启动
     void CFRunLoopRun(void) {
     CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
     }
     */
    //        CFRunLoopRun()
    
    
    /**
     *  使用指定mode启动，允许设置runloop超时时间
     int CFRunLoopRunInMode(CFStringRef modeName, CFTimeInterval seconds, Boolean stopAfterHandle) {
     return CFRunLoopRunSpecific(CFRunLoopGetCurrent(), modeName, seconds, returnAfterSourceHandled);
     }
     */
    //        CFRunLoopRunInMode(<#T##mode: CFString!##CFString!#>, <#T##seconds: CFTimeInterval##CFTimeInterval#>, <#T##returnAfterSourceHandled: Bool##Bool#>)
    
    
    
    //Core Foundation和Foundation为Mach端口提供了高级API。在内核基础上封装的CFMachPort / NSMachPort可以用做runloop源，尽管CFMachPort / NSMachPort有利于的是两个不同端口之间的通讯同步。
    
    //CFMessagePort确实非常适合用于简单的一对一通讯。简简单单几行代码，一个本地端口就被附属到runloop源上，只要获取到消息就执行回调。
    
//    CFMessagePortRef localPort = CFMessagePortCreateLocal(kCFAllocatorDefault, CFSTR("com.example.app.port.server"), Callback, nil, nil);
//    
//    CFRunLoopSourceRef runLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, localPort, 0);
//    
//    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
//    
//    //若要进行发送数据同样也十分直截了当。只要完成指定远端的端口，装载数据，还有设置发送与接收的超时时间的操作。剩下就由CFMessagePortSendRequest来接管了。
//    
//    CFDataRef data;
//    SInt32 messageID = 0x1111; // Arbitrary
//    CFTimeInterval timeout = 10.0;
//    
//    CFMessagePortRef remotePort =
//    CFMessagePortCreateRemote(nil,
//                              CFSTR("com.example.app.port.client"));
//    
//    SInt32 status =
//    CFMessagePortSendRequest(remotePort,
//                             messageID,
//                             data,
//                             timeout,
//                             timeout,
//                             NULL,
//                             NULL);
//    if (status == kCFMessagePortSuccess) {
//        // ...
//    }
    
    
    
    //想知道发了多少次广播吗？添加 NSNotificationCenter addObserverForName:object:queue:usingBlock，其中name与object置nil，看block被调用了几次。
//    observer = [[NSNotificationCenter defaultCenter]addObserverForName:nil object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
////        NSLog(@"===========%@", note);
//    }];
    
    
    //不知道啥玩意。。。
    //接收
//    CFNotificationCenterRef distributedCenterGet = CFNotificationCenterGetDarwinNotifyCenter();
//    CFNotificationSuspensionBehavior behavior = CFNotificationSuspensionBehaviorDeliverImmediately;
//    CFNotificationCenterAddObserver(distributedCenterGet, NULL, NotifyCallback, CFSTR("notification.identifier"), NULL, behavior);
//    
//    
//    //发送
//    void *object;
//    CFDictionaryRef userInfo;
//    
//    CFNotificationCenterRef distributedCenterPost =
//    CFNotificationCenterGetDarwinNotifyCenter();
//    CFNotificationCenterPostNotification(distributedCenterPost,
//                                         CFSTR("notification.identifier"),
//                                         object,
//                                         userInfo,
//                                         true);
    
    
    scrollView = [[UIScrollView alloc]initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, self.view.bounds.size.height)];
    
    UIView *headerView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, scrollView.bounds.size.width, 100)];
    headerView.backgroundColor = [UIColor redColor];
    
    [self.view addSubview:scrollView];
    [self.view addSubview:headerView];
    
    scrollView.contentSize = CGSizeMake(scrollView.bounds.size.width, 999);
    scrollView.backgroundColor = [UIColor greenColor];
    
    
    
    //监听状态
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopEntry, true, -1, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSLog(@"kCFRunLoopEntry....");
    });
    CFRunLoopObserverRef observer2 = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopBeforeTimers, true, -1, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSLog(@"kCFRunLoopBeforeTimers....");
    });
    CFRunLoopObserverRef observer3 = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopBeforeSources, true, -1, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        
//        CGPoint trans = [scrollView.panGestureRecognizer translationInView:scrollView];
//        if (trans.y > -100) {
//            self.view.layer.transform = CATransform3DMakeTranslation(0, trans.y, 0);
//            scrollView.contentOffset = CGPointZero;
//        }else {
//            
//        }
//        cancel = !cancel;
//        NSLog(@"kCFRunLoopBeforeSources....");
    });
    CFRunLoopObserverRef observer6 = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopExit, true, -1, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSLog(@"kCFRunLoopBeforeWaiting....");
    });
    CFRunLoopObserverRef observer5 = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAfterWaiting, true, -1, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSLog(@"kCFRunLoopAfterWaiting....");
    });
    
    
    CFRunLoopObserverContext context = {
        .version = 0,
        .info = (__bridge void *)self,
        NULL,
        NULL,
        NULL
    };
    
    CFRunLoopObserverRef observer4 = CFRunLoopObserverCreate(nil, kCFRunLoopBeforeWaiting, true, 0, &ObserverCallback, &context);
    
    CFStringRef str = (__bridge CFStringRef)UITrackingRunLoopMode;
    
//    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, str);
//    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer2, str);
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer3, str);
//    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer4, str);
//    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer5, str);
//    CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer6, str);
    
    
    //添加事件源
//    CFRunLoopSourceContext ctx = {
//        .version = 0,
//        .info = (__bridge void *)self,
//        NULL,
//        NULL,
//        NULL,
//        NULL,
//        NULL,
//        NULL,
//        NULL,
////        Boolean	(*equal)(const void *info1, const void *info2);
////        CFHashCode	(*hash)(const void *info);
////        void	(*schedule)(void *info, CFRunLoopRef rl, CFStringRef mode);
////        void	(*cancel)(void *info, CFRunLoopRef rl, CFStringRef mode);
////        void	(*perform)(void *info);
//        .perform = _perform
//    };
//    
//    //该source需要CFRunLoopSourceSignal激活
//    CFRunLoopSourceRef source = CFRunLoopSourceCreate(nil, 0, &ctx);
//    
//    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, str);
////    CFRunLoopSourceSignal(source);
//    
//    //添加定时器
//    CFRunLoopTimerContext ctx2 = {
//        .version = 0,
//        .info = source,
//        NULL,
//        NULL,
//        NULL
//    };
//    
//    //在定时器中模拟触发source
//    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent(), 1, 0, 0, &_timer, &ctx2);
//    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, str);
    
//    CFRunLoopRunResult result = CFRunLoopRunInMode(str, 10, false);
//    
//    NSLog(@"%d",result);
    
    
    //利用dispatch添加source
//    dispatch_source_t source2 = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
//    dispatch_source_set_event_handler(source2, ^{
//        printf("source2.....");
//    });
//    dispatch_resume(source2);
//    
//    dispatch_source_t timer2 = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
//    dispatch_source_set_timer(timer2, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 0 * NSEC_PER_SEC);
//    dispatch_source_set_event_handler(timer2, ^{
//        dispatch_source_merge_data(source2, 1);
//    });
//    dispatch_resume(timer2);
//    
//    dispatch_main();
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTimer *timer = [NSTimer timerWithTimeInterval:2 target:self selector:@selector(doTask) userInfo:nil repeats:YES];
        
        runloop = [NSRunLoop currentRunLoop];
        
        [runloop addTimer:timer forMode:NSDefaultRunLoopMode];
        
        //如果这里给UITrackingRunLoopMode下的runloop加一个port，runloop就不会退出了，看warning，AFN就是这么做的
        [runloop addPort:[NSPort port] forMode:UITrackingRunLoopMode];
        
        while (!cancel) {
            
            [self doOtherTask];
            
            //- (void)run; 无条件运行不建议使用，因为这个接口会导致Run Loop永久性的运行在NSDefaultRunLoopMode模式，即使使用CFRunLoopStop(runloopRef);也无法停止Run Loop的运行，那么这个子线程就无法停止，只能永久运行下去。
            
            //- (void)runUntilDate:(NSDate *)limitDate;有个超时时间，可以控制每次Run Loop的运行时间，也是运行在NSDefaultRunLoopMode模式。这个方法运行Run Loop一段时间会退出给你检查运行条件的机会，如果需要可以再次运行Run Loop。注意CFRunLoopStop(runloopRef);也无法停止Run Loop的运行，因此最好自己设置一个合理的Run Loop运行时间
            
            //- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limitDate;这个接口在非Timer事件触发、显式的用CFRunLoopStop停止Run Loop、到达limitDate后会退出返回。如果仅是Timer事件触发并不会让Run Loop退出返回；如果是PerfromSelector*事件或者其他Input Source事件触发处理后，Run Loop会退出返回YES。
#warning runloop如果runmode为UITrackingRunLoopMode，而timer是NSDefaultRunLoopMode，意味着这个模式下的runloop是没有timer的，一个runloop如果没有timer/source/port，会自动退出
            BOOL ret = [[NSRunLoop currentRunLoop] runMode:UITrackingRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:4]];
            NSLog(@"after runloop counting.........: %d", ret);
        }
        
        NSLog(@"thread exit");
    });
    
}

- (void)doTask {
    NSLog(@"do task");
}

- (void)doOtherTask {
    NSLog(@"do other task");
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    
}

- (void)dealloc
{
//    [[NSNotificationCenter defaultCenter]removeObserver:observer];
}


@end
