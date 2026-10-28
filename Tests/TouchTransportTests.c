#include "touchcontroller/PocketJTouchTransport.h"
#include "jni.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <arpa/inet.h>
extern void Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_init(JNIEnv *,jclass);
extern jlong Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_new(JNIEnv *,jclass,jstring);
typedef struct { int size; unsigned char bytes[4096]; } TestArray;
static int legacy;
static void *reader,*writer;
static jmethodID getMethod(JNIEnv *env,jclass cls,const char *name,const char *signature) {
    if(!strcmp(name,"receive") && !strcmp(signature,legacy ? "(J[B)I":"([B)I")) return (jmethodID)(uintptr_t)1;
    return NULL;
}
static jboolean exception(JNIEnv *env) { return JNI_FALSE; }
static void clearException(JNIEnv *env) {}
static jint registerMethods(JNIEnv *env,jclass cls,const JNINativeMethod *methods,jint count) {
    assert(count==2); reader=methods[0].fnPtr; writer=methods[1].fnPtr; return 0;
}
static jsize length(JNIEnv *env,jarray array) { return ((TestArray *)array)->size; }
static void getBytes(JNIEnv *env,jbyteArray array,jsize offset,jsize count,jbyte *buffer) { memcpy(buffer,((TestArray *)array)->bytes+offset,count); }
static void setBytes(JNIEnv *env,jbyteArray array,jsize offset,jsize count,const jbyte *buffer) { memcpy(((TestArray *)array)->bytes+offset,buffer,count); }
int main(void) {
    struct JNINativeInterface functions={0};
    functions.GetStaticMethodID=getMethod; functions.GetMethodID=getMethod;
    functions.ExceptionCheck=exception; functions.ExceptionClear=clearException;
    functions.RegisterNatives=registerMethods; functions.GetArrayLength=length;
    functions.GetByteArrayRegion=getBytes; functions.SetByteArrayRegion=setBytes;
    JNIEnv env=&functions;
    for(legacy=0;legacy<2;legacy++) {
        PJTouchReset(); reader=writer=NULL;
        Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_init(&env,NULL);
        assert(reader && writer); assert(!PJTouchReady());
        TestArray input={.size=4}; uint32_t init=htonl(10); memcpy(input.bytes,&init,4);
        if(legacy) { assert(Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_new(&env,NULL,NULL)==1); ((void (*)(JNIEnv *,jclass,jlong,jbyteArray,jint,jint))writer)(&env,NULL,1,(jbyteArray)&input,0,4); }
        else ((void (*)(JNIEnv *,jclass,jbyteArray,jint,jint))writer)(&env,NULL,(jbyteArray)&input,0,4);
        assert(PJTouchReady()); unsigned char buffer[4096];
        assert(PJTouchReceive(buffer,2)==-2); assert(PJTouchReceive(buffer,sizeof(buffer))==4);
        assert(!memcmp(buffer,input.bytes,4)); assert(PJTouchReceive(buffer,sizeof(buffer))==0);
        uint32_t pointer[4]={htonl(1),htonl(7),0,0}; PJTouchSend(pointer,sizeof(pointer));
        TestArray output={.size=4096};
        int size=legacy ? ((jint (*)(JNIEnv *,jclass,jlong,jbyteArray))reader)(&env,NULL,1,(jbyteArray)&output)
                        : ((jint (*)(JNIEnv *,jclass,jbyteArray))reader)(&env,NULL,(jbyteArray)&output);
        assert(size==16 && !memcmp(output.bytes,pointer,16));
        for(int i=0;i<10000;i++) PJTouchSend(pointer,16);
        uint32_t remove[2]={htonl(2),htonl(7)}; PJTouchSend(remove,8);
        int last=0, count=0;
        while((size=legacy ? ((jint (*)(JNIEnv *,jclass,jlong,jbyteArray))reader)(&env,NULL,1,(jbyteArray)&output) : ((jint (*)(JNIEnv *,jclass,jbyteArray))reader)(&env,NULL,(jbyteArray)&output))>0) { last=size; count++; }
        assert(count<=128 && last==8); // queue bounded; final pointer release survives
    }
    PJTouchReset(); puts("PASS: modern/legacy JNI binding, handshake, bounded queues and pointer release.");
    return 0;
}
