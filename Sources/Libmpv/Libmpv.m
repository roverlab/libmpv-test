#import "Libmpv.h"

// Version information
double LibmpvVersionNumber = 1.0;
const unsigned char LibmpvVersionString[] = "1.0";

// Re-export mpv client API for Swift access
#include <mpv/client.h>
#include <mpv/render.h>

// Ensure symbols are exported
__attribute__((visibility("default")))
extern "C" {
    // MPV Client API wrappers
    mpv_handle *mpv_create(void) {
        return ::mpv_create();
    }
    
    int mpv_initialize(mpv_handle *handle) {
        return ::mpv_initialize(handle);
    }
    
    void mpv_terminate_destroy(mpv_handle *handle) {
        ::mpv_terminate_destroy(handle);
    }
    
    int mpv_command(mpv_handle *handle, const char **args) {
        return ::mpv_command(handle, args);
    }
    
    int mpv_command_string(mpv_handle *handle, const char *args) {
        return ::mpv_command_string(handle, args);
    }
    
    mpv_event *mpv_wait_event(mpv_handle *handle, double timeout) {
        return ::mpv_wait_event(handle, timeout);
    }
    
    int mpv_set_property(mpv_handle *handle, const char *name, mpv_format format, void *data) {
        return ::mpv_set_property(handle, name, format, data);
    }
    
    const char *mpv_error_string(int error) {
        return ::mpv_error_string(error);
    }
}