// Native bridge regressions using only fake objects. This test must never
// create an EKEventStore or request access to the user's system calendars.
#import "../science_calendar_darwin.m"
@interface SciFakeTask : NSObject
@property(nonatomic, copy) NSURL *URL;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) NSDateComponents *dueDateComponents;
@property(nonatomic, readonly) NSString *calendarItemIdentifier;
@property(nonatomic, copy) NSString *notes;
@end
@implementation SciFakeTask
- (NSString *)calendarItemIdentifier { return @"sci-eventkit-test-identifier"; }
@end

@interface SciFakeDefaults : NSObject
@property(nonatomic, copy) NSString *identifier;
@end
@implementation SciFakeDefaults
- (NSString *)stringForKey:(NSString *)key { return self.identifier; }
- (void)setObject:(NSString *)value forKey:(NSString *)key { self.identifier = value; }
@end

static EKAuthorizationStatus fakeAuthorization;
@interface SciFakeStore : NSObject
@property(nonatomic, strong) SciFakeTask *task;
@property(nonatomic) NSUInteger saves;
@property(nonatomic) BOOL shouldFailSave;
@end
@implementation SciFakeStore
+ (EKAuthorizationStatus)authorizationStatusForEntityType:(EKEntityType)kind { return fakeAuthorization; }
- (EKCalendarItem *)calendarItemWithIdentifier:(NSString *)identifier { return nil; }
- (NSPredicate *)predicateForRemindersInCalendars:(NSArray<EKCalendar *> *)calendars { return nil; }
- (id)fetchRemindersMatchingPredicate:(NSPredicate *)predicate completion:(void (^)(NSArray<EKReminder *> *))completion {
    completion(@[(EKReminder *)self.task]);
    return nil;
}
- (BOOL)saveReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error {
    if (self.shouldFailSave) {
        *error = [NSError errorWithDomain:@"SciFakeEventKit" code:1 userInfo:@{NSLocalizedDescriptionKey:@"save failed"}];
        return NO;
    }
    self.saves++;
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        NSDateComponents *allDay = sciReminderDueComponents(@"2026-11-25");
        NSDateComponents *time = sciReminderDueComponents(@"2026-11-25T00:05");
        if (allDay.hour != NSDateComponentUndefined || allDay.day != 25 || time.hour != 0 || time.minute != 5) return 5;
        if (sciReminderDueComponents(@"") != nil) return 6;
        NSString *marker = @"sci-station://tasks/test";
        SciFakeTask *task = [[SciFakeTask alloc] init];
        task.notes = [@"unrelated " stringByAppendingString:marker];
        if (sciMatchesTask((EKReminder *)task, marker)) return 1;
        task.notes = [@"user text\n\n" stringByAppendingString:marker];
        if (!sciMatchesTask((EKReminder *)task, marker)) return 2;
        task.notes = nil;
        task.URL = [NSURL URLWithString:marker];
        if (!sciMatchesTask((EKReminder *)task, marker)) return 3;

        SciFakeStore *fake = [[SciFakeStore alloc] init];
        fake.task = task;
        fakeAuthorization = EKAuthorizationStatusDenied;
        EKEventStore *store = (EKEventStore *)fake;
        NSUserDefaults *defaults = (NSUserDefaults *)[[SciFakeDefaults alloc] init];
        if (![sciPublish(store, defaults, marker, @"First", @"Details", @"2026-11-25")[@"error"] length] || fake.saves != 0) return 7;
        if (@available(macOS 14.0, *)) {
            fakeAuthorization = EKAuthorizationStatusFullAccess;
        } else {
            fakeAuthorization = EKAuthorizationStatusAuthorized;
        }
        if (![sciPublish(store, defaults, marker, @"First", @"Details", @"2026-11-25")[@"value"] isEqual:task.calendarItemIdentifier]) return 8;
        if (fake.saves != 1 || ![task.title isEqual:@"First"] || task.dueDateComponents.hour != NSDateComponentUndefined) return 9;
        fake.shouldFailSave = YES;
        if (![sciPublish(store, defaults, marker, @"Edited", @"New notes", @"2026-11-26T14:30")[@"error"] isEqual:@"save failed"]) return 10;
        fake.shouldFailSave = NO;
        if (![sciPublish(store, defaults, marker, @"Edited", @"New notes", @"2026-11-26T14:30")[@"value"] isEqual:task.calendarItemIdentifier]) return 11;
        if (fake.saves != 2 || ![task.title isEqual:@"Edited"] || task.dueDateComponents.hour != 14 ||
            task.dueDateComponents.minute != 30 || ![task.notes containsString:@"New notes"]) return 12;

        char *response = sciEventKitRequest(^NSDictionary *(EKEventStore *store) {
            abort();  // Calling from the main thread never creates or accesses the real store.
        });
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:response] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        free(response);
        if (![body[@"error"] length]) return 4;
    }
    return 0;
}
