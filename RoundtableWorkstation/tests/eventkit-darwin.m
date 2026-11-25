// Native bridge regressions using only fake objects. This test must never
// create an EKEventStore or request access to the user's system calendars.
#import "../science_calendar_darwin.m"
@interface SciFakeTask : NSObject
@property(nonatomic, copy) NSURL *URL;
@property(nonatomic, copy) NSString *notes;
@end
@implementation SciFakeTask
@end
int main(void) {
    @autoreleasepool {
        NSString *marker = @"sci-station://tasks/test";
        SciFakeTask *task = [[SciFakeTask alloc] init];
        task.notes = [@"unrelated " stringByAppendingString:marker];
        if (sciMatchesTask((EKReminder *)task, marker)) return 1;
        task.notes = [@"user text\n\n" stringByAppendingString:marker];
        if (!sciMatchesTask((EKReminder *)task, marker)) return 2;
        task.notes = nil;
        task.URL = [NSURL URLWithString:marker];
        if (!sciMatchesTask((EKReminder *)task, marker)) return 3;
        char *response = sciEventKitRequest(^NSDictionary *(EKEventStore *store) {
            abort();  // Calling from the main thread never creates or accesses the real store.
        });
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:response] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        free(response);
        if (![body[@"error"] length]) return 4;
    }
    return 0;
}
