/*
 *  bscommon.c
 *  Sparkle
 *
 *  Created by Mayur Pawashe on 5/16/16.
 */

#include "bscommon.h"
#include <stdlib.h>

u_char *readfile(const char *filename, off_t *outSize)
{
    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        return NULL;
    }
    
    if (fseek(file, 0L, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    
    long offset = ftell(file);
    if (offset == -1) {
        fclose(file);
        return NULL;
    }
    
    size_t size = (size_t)offset;
    
    if (outSize != NULL) {
        *outSize = (off_t)size;
    }
    
    /* Allocate size + 1 bytes instead of newsize bytes to ensure
     that we never try to malloc(0) and get a NULL pointer */
    u_char *buffer = malloc(size + 1);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }
    
    if (fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    
    if (fread(buffer, 1, size, file) < size) {
        fclose(file);
        return NULL;
    }
    
    fclose(file);
    
    return buffer;
}
