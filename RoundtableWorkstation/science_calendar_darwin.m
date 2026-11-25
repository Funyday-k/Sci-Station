//go:build darwin && cgo && !nogui

#import <Foundation/Foundation.h>
#import <EventKit/EventKit.h>
#include <string.h>

static const NSTimeInterval sciEventKitTimeout = 120;
static dispatch_queue_t sciEventKitQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("sci-station.eventkit", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static EKEventStore *sciEventKitStore(void) {
    static EKEventStore *store;
    if (!store) store = [[EKEventStore alloc] init];
    return store;
}

static NSString *sciAccessError(EKEventStore *store, EKEntityType kind) {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:kind];
    NSString *name = kind == EKEntityTypeEvent ? @"日历" : @"提醒事项";
    NSString *denied = [NSString stringWithFormat:@"请在“系统设置 → 隐私与安全性 → %@”中授权 Sci-Station 访问。", name];
    if (@available(macOS 14.0, *)) {
        if (status == EKAuthorizationStatusFullAccess) return nil;
    } else {
        if (status == EKAuthorizationStatusAuthorized) return nil;
    }
    if (status == EKAuthorizationStatusDenied || status == EKAuthorizationStatusRestricted) return denied;
    __block BOOL allowed = NO;
    __block NSError *issue = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    EKEventStoreRequestAccessCompletionHandler completion = ^(BOOL granted, NSError *error) {
        allowed = granted;
        issue = error;
        dispatch_semaphore_signal(done);
    };
    if (@available(macOS 14.0, *)) {
        if (kind == EKEntityTypeEvent) [store requestFullAccessToEventsWithCompletion:completion];
        else [store requestFullAccessToRemindersWithCompletion:completion];
    } else {
        [store requestAccessToEntityType:kind completion:completion];
    }
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sciEventKitTimeout * NSEC_PER_SEC)))) {
        return @"等待系统授权超时。请检查系统权限提示后重试。";
    }
    if (issue) return issue.localizedDescription;
    return allowed ? nil : denied;
}

static char *sciEventKitJSON(NSDictionary *result) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (!data) return strdup("{\"error\":\"系统日历返回结果无效\"}");
    return strndup(data.bytes, data.length);
}

static NSDictionary *sciUpcoming(EKEventStore *store) {
    NSString *error = sciAccessError(store, EKEntityTypeEvent);
    if (error) return @{@"error":error};
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *start = [cal startOfDayForDate:NSDate.date];
    NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:30 toDate:start options:0];
    NSPredicate *predicate = [store predicateForEventsWithStartDate:start endDate:end calendars:nil];
    NSArray<EKEvent *> *events = [[store eventsMatchingPredicate:predicate]
                                 sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    // Preserve the user's local offset on all-day event boundaries.
    iso.timeZone = NSTimeZone.localTimeZone;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:events.count];
    for (EKEvent *item in events) {
        if (!item.startDate || !item.endDate) continue;
        [items addObject:@{@"title":item.title ?: @"", @"calendar":item.calendar.title ?: @"",
                           @"start":[iso stringFromDate:item.startDate], @"end":[iso stringFromDate:item.endDate]}];
    }
    return @{@"value":items};
}

static BOOL sciMatchesTask(EKReminder *item, NSString *marker) {
    // Some account providers do not persist the URL property. Keep the marker
    // as a whole line in the note as a second stable identity for a moved item.
    return [item.URL.absoluteString isEqualToString:marker] ||
        [[item.notes componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] containsObject:marker];
}

static EKReminder *sciFindReminder(EKEventStore *store, NSString *marker, NSString **reason) {
    NSString *cacheKey = [@"SciStationReminder." stringByAppendingString:marker];
    NSString *identifier = [NSUserDefaults.standardUserDefaults stringForKey:cacheKey];
    if (identifier.length) {
        EKCalendarItem *cached = [store calendarItemWithIdentifier:identifier];
        if ([cached isKindOfClass:EKReminder.class] && sciMatchesTask((EKReminder *)cached, marker)) return (EKReminder *)cached;
    }
    __block EKReminder *existing = nil;
    __block BOOL loaded = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSPredicate *predicate = [store predicateForRemindersInCalendars:nil];
    id fetch = [store fetchRemindersMatchingPredicate:predicate completion:^(NSArray<EKReminder *> *reminders) {
        loaded = reminders != nil;
        for (EKReminder *item in reminders) {
            if (sciMatchesTask(item, marker)) { existing = item; break; }
        }
        dispatch_semaphore_signal(done);
    }];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sciEventKitTimeout * NSEC_PER_SEC)))) {
        [store cancelFetchRequest:fetch];
        *reason = @"检查既有提醒事项超时，请重试。";
        return nil;
    }
    if (!loaded) *reason = @"无法核对已发布的提醒事项，请检查提醒事项账户。";
    return existing;
}

static NSDictionary *sciPublish(EKEventStore *store, NSString *marker, NSString *title,
                                NSString *detail, NSString *dueDate) {
    NSString *issue = sciAccessError(store, EKEntityTypeReminder);
    if (issue) return @{@"error":issue};
    EKReminder *item = sciFindReminder(store, marker, &issue);
    if (issue) return @{@"error":issue};
    if (!item) {
        EKCalendar *calendar = [store defaultCalendarForNewReminders];
        if (!calendar || !calendar.allowsContentModifications) return @{@"error":@"请先在“提醒事项”中配置一个可写的默认列表。"};
        item = [EKReminder reminderWithEventStore:store];
        item.calendar = calendar;
    }

    item.title = title;
    item.URL = [NSURL URLWithString:marker];
    item.notes = detail.length ? [NSString stringWithFormat:@"%@\n\n%@", detail, marker] : marker;
    NSDateComponents *due = nil;
    if (dueDate.length) {
        NSArray<NSString *> *parts = [dueDate componentsSeparatedByString:@"-"];
        due = [[NSDateComponents alloc] init];
        due.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        due.year = parts[0].integerValue;
        due.month = parts[1].integerValue;
        due.day = parts[2].integerValue;
    }
    item.dueDateComponents = due;
    NSError *error = nil;
    if (![store saveReminder:item commit:YES error:&error]) return @{@"error":error.localizedDescription ?: @"提醒事项保存失败。"};
    NSString *identifier = item.calendarItemIdentifier;
    if (!identifier.length) return @{@"error":@"系统未返回提醒事项标识，请重新核对后重试。"};
    [NSUserDefaults.standardUserDefaults setObject:identifier forKey:[@"SciStationReminder." stringByAppendingString:marker]];
    return @{@"value":identifier};
}

static char *sciEventKitRequest(NSDictionary *(^action)(EKEventStore *)) {
    @autoreleasepool {
        if (NSThread.isMainThread) return sciEventKitJSON(@{@"error":@"系统日历请求需要在后台执行。"});
        __block NSDictionary *result = nil;
        dispatch_sync(sciEventKitQueue(), ^{
            @autoreleasepool { result = action(sciEventKitStore()); }
        });
        return sciEventKitJSON(result);
    }
}

char *sciCalendarUpcoming(void) {
    return sciEventKitRequest(^NSDictionary *(EKEventStore *store) { return sciUpcoming(store); });
}

char *sciCalendarPublish(const char *marker, const char *title, const char *detail, const char *due) {
    return sciEventKitRequest(^NSDictionary *(EKEventStore *store) {
        return sciPublish(store, [NSString stringWithUTF8String:marker], [NSString stringWithUTF8String:title],
                          [NSString stringWithUTF8String:detail], [NSString stringWithUTF8String:due]);
    });
}
