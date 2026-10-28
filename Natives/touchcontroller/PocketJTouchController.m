#import "PocketJTouchController.h"
#import "PocketJTouchTransport.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
@interface PocketJTouchController () {
    int _socket;
}
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL udp;
@property(nonatomic) NSMapTable<UITouch *,NSNumber *> *fingers;
@end
@implementation PocketJTouchController
- (instancetype)initWithMode:(NSString *)mode {
    if ((self=[super init])) {
        _socket=-1; _udp=[mode isEqual:@"udp"]; _fingers=[NSMapTable strongToStrongObjectsMapTable];
        if (_udp) { _socket=socket(AF_INET6,SOCK_DGRAM,0); if (_socket>=0) { fcntl(_socket,F_SETFL,O_NONBLOCK); _ready=YES; } }
        else PJTouchReset();
    } return self;
}
- (void)send:(NSData *)packet {
    if (!self.udp) { PJTouchSend(packet.bytes,(int)packet.length); return; }
    struct sockaddr_in6 address={0}; address.sin6_family=AF_INET6; address.sin6_port=htons(12450); address.sin6_addr=in6addr_loopback;
    sendto(_socket,packet.bytes,packet.length,0,(struct sockaddr *)&address,sizeof(address));
}
- (void)poll {
    if (self.udp) return;
    if (!self.ready && PJTouchReady()) { self.ready=YES; if(self.readyHandler) self.readyHandler(); }
    uint8_t data[4096]; int size;
    // Bounded work per frame; a noisy mod cannot monopolize the main thread.
    for (NSUInteger count=0;count<32 && (size=PJTouchReceive(data,sizeof(data)))>0;count++) {
        if(size<4) continue; uint32_t encoded; memcpy(&encoded,data,4); uint32_t type=ntohl(encoded);
        if(type==10) {
            const char *name="keyboard_show"; uint32_t cap=htonl(5); uint8_t length=(uint8_t)strlen(name), enabled=1;
            NSMutableData *message=[NSMutableData dataWithBytes:&cap length:4]; [message appendBytes:&length length:1]; [message appendBytes:name length:length]; [message appendBytes:&enabled length:1]; [self send:message];
        } else if(type==8 && size==5 && self.keyboardHandler) self.keyboardHandler(data[4]!=0);
        else if(type==4 && size==8) { UIImpactFeedbackGenerator *feedback=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feedback impactOccurred]; }
    }
}
- (void)sendFinger:(int32_t)finger point:(CGPoint)point ended:(BOOL)ended {
    uint32_t packet[4]={htonl(ended ? 2:1),htonl((uint32_t)finger),0,0};
    float x=point.x,y=point.y; uint32_t bits; memcpy(&bits,&x,4); packet[2]=htonl(bits); memcpy(&bits,&y,4); packet[3]=htonl(bits);
    [self send:[NSData dataWithBytes:packet length:ended ? 8:16]];
}
- (BOOL)routeTouches:(NSSet<UITouch *> *)touches view:(UIView *)view ended:(BOOL)ended {
    if(!self.ready || view.bounds.size.width<=0 || view.bounds.size.height<=0) return NO;
    BOOL routed=NO;
    for(UITouch *touch in touches) {
        if(touch.type==UITouchTypeIndirectPointer) continue;
        NSNumber *finger=[self.fingers objectForKey:touch];
        if(!finger && !ended) {
            NSSet *used=[NSSet setWithArray:self.fingers.objectEnumerator.allObjects];
            for(NSInteger n=0;n<32;n++) if(![used containsObject:@(n)]) { finger=@(n); [self.fingers setObject:finger forKey:touch]; break; }
        }
        if(!finger) continue;
        CGPoint point=[touch locationInView:view]; point.x=MAX(0,MIN(1,point.x/view.bounds.size.width)); point.y=MAX(0,MIN(1,point.y/view.bounds.size.height));
        [self sendFinger:finger.intValue point:point ended:ended]; if(ended) [self.fingers removeObjectForKey:touch]; routed=YES;
    } return routed;
}
- (void)releasePointers {
    for(NSNumber *finger in self.fingers.objectEnumerator) [self sendFinger:finger.intValue point:CGPointZero ended:YES];
    [self.fingers removeAllObjects];
}
- (void)dealloc { [self releasePointers]; if(_socket>=0) close(_socket); }
@end
