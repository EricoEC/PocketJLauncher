/* PocketJ clean implementation of the public TouchController transport ABI.
 * Protocol reference: TouchController/TouchController, LGPL-3.0-or-later.
 * No private handles are cast to pointers. Both JNI ABIs bind by signature.
 */
#include "PocketJTouchTransport.h"
#include "jni.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>

enum { PJ_PACKET_MAX=4096, PJ_QUEUE_MAX=128 };
typedef struct PJPacket { struct PJPacket *next; int size; unsigned char data[]; } PJPacket;
typedef struct { PJPacket *first,*last; int count; } PJQueue;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static PJQueue toHost[2],toMod[2];
static int nativeReady,legacyActive,modernActive;
static void clear(PJQueue *q) { while(q->first) { PJPacket *next=q->first->next; free(q->first); q->first=next; } q->last=NULL; q->count=0; }
static void push(PJQueue *q,const void *data,int size) {
    if (!data || size<=0 || size>PJ_PACKET_MAX) return;
    if (q->count>=PJ_QUEUE_MAX) { PJPacket *old=q->first; q->first=old->next; q->count--; free(old); if(!q->first) q->last=NULL; }
    PJPacket *packet=malloc(sizeof(PJPacket)+(size_t)size); if (!packet) return;
    packet->next=NULL; packet->size=size; memcpy(packet->data,data,(size_t)size);
    if(q->last) q->last->next=packet; else q->first=packet; q->last=packet; q->count++;
}
static int pop(PJQueue *q,void *data,int capacity) {
    if(!q->first) return 0; if(capacity<q->first->size) return -2;
    PJPacket *packet=q->first; int size=packet->size; memcpy(data,packet->data,(size_t)size);
    q->first=packet->next; if(!q->first) q->last=NULL; q->count--; free(packet); return size;
}
void PJTouchReset(void) { pthread_mutex_lock(&lock); for(int i=0;i<2;i++) { clear(&toHost[i]); clear(&toMod[i]); } nativeReady=legacyActive=modernActive=0; pthread_mutex_unlock(&lock); }
int PJTouchReady(void) { pthread_mutex_lock(&lock); int ready=nativeReady; pthread_mutex_unlock(&lock); return ready; }
int PJTouchReceive(void *data,int capacity) { pthread_mutex_lock(&lock); int n=pop(&toHost[0],data,capacity); if(!n) n=pop(&toHost[1],data,capacity); pthread_mutex_unlock(&lock); return n; }
void PJTouchSend(const void *data,int size) { pthread_mutex_lock(&lock); if(modernActive) push(&toMod[0],data,size); if(legacyActive) push(&toMod[1],data,size); pthread_mutex_unlock(&lock); }
static void fromMod(int channel,const void *data,int size) {
    if(size<4 || size>PJ_PACKET_MAX) return;
    pthread_mutex_lock(&lock);
    if(channel) legacyActive=1; else modernActive=1;
    uint32_t type; memcpy(&type,data,4); if(ntohl(type)==10) nativeReady=1;
    push(&toHost[channel],data,size); pthread_mutex_unlock(&lock);
}
static jint readJava(JNIEnv *env,int channel,jbyteArray array) {
    if(!array) return -1; jsize capacity=(*env)->GetArrayLength(env,array); unsigned char data[PJ_PACKET_MAX];
    pthread_mutex_lock(&lock); int size=pop(&toMod[channel],data,capacity<PJ_PACKET_MAX ? capacity:PJ_PACKET_MAX); pthread_mutex_unlock(&lock);
    if(size>0) (*env)->SetByteArrayRegion(env,array,0,size,(const jbyte *)data); return size;
}
static void writeJava(JNIEnv *env,int channel,jbyteArray array,jint offset,jint length) {
    if(!array || offset<0 || length<4 || length>PJ_PACKET_MAX) return;
    jsize capacity=(*env)->GetArrayLength(env,array); if(offset>capacity || length>capacity-offset) return;
    unsigned char data[PJ_PACKET_MAX]; (*env)->GetByteArrayRegion(env,array,offset,length,(jbyte *)data);
    if(!(*env)->ExceptionCheck(env)) fromMod(channel,data,length);
}
static jint modernRead(JNIEnv *env,jclass cls,jbyteArray array) { return readJava(env,0,array); }
static void modernWrite(JNIEnv *env,jclass cls,jbyteArray array,jint offset,jint length) { writeJava(env,0,array,offset,length); }
static jint legacyRead(JNIEnv *env,jclass cls,jlong handle,jbyteArray array) { return handle==1 ? readJava(env,1,array):-1; }
static void legacyWrite(JNIEnv *env,jclass cls,jlong handle,jbyteArray array,jint offset,jint length) { if(handle==1) writeJava(env,1,array,offset,length); }
static int hasMethod(JNIEnv *env,jclass cls,const char *name,const char *signature) {
    jmethodID method=(*env)->GetStaticMethodID(env,cls,name,signature);
    if((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
    if(!method) { method=(*env)->GetMethodID(env,cls,name,signature); if((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env); }
    return method!=NULL;
}
JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_init(JNIEnv *env,jclass cls) {
    if(hasMethod(env,cls,"receive","([B)I")) {
        JNINativeMethod methods[]={{"receive","([B)I",(void *)modernRead},{"send","([BII)V",(void *)modernWrite}};
        (*env)->RegisterNatives(env,cls,methods,2);
    } else if(hasMethod(env,cls,"receive","(J[B)I")) {
        JNINativeMethod methods[]={{"receive","(J[B)I",(void *)legacyRead},{"send","(J[BII)V",(void *)legacyWrite}};
        (*env)->RegisterNatives(env,cls,methods,2);
    }
}
JNIEXPORT jlong JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_new(JNIEnv *env,jclass cls,jstring path) { pthread_mutex_lock(&lock); legacyActive=1; pthread_mutex_unlock(&lock); return 1; }
JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_destroy(JNIEnv *env,jclass cls,jlong handle) { if(handle!=1) return; pthread_mutex_lock(&lock); clear(&toMod[1]); clear(&toHost[1]); legacyActive=0; pthread_mutex_unlock(&lock); }
JNIEXPORT jint JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_receive___3B(JNIEnv *env,jclass cls,jbyteArray array) { return modernRead(env,cls,array); }
JNIEXPORT jint JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_receive__J_3B(JNIEnv *env,jclass cls,jlong handle,jbyteArray array) { return legacyRead(env,cls,handle,array); }
JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_send___3BII(JNIEnv *env,jclass cls,jbyteArray array,jint offset,jint length) { modernWrite(env,cls,array,offset,length); }
JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_send__J_3BII(JNIEnv *env,jclass cls,jlong handle,jbyteArray array,jint offset,jint length) { legacyWrite(env,cls,handle,array,offset,length); }
