#pragma once
#include <stdint.h>
#include <stddef.h>
void PJTouchReset(void);
int PJTouchReady(void);
int PJTouchReceive(void *buffer, int capacity);
void PJTouchSend(const void *buffer, int size);
