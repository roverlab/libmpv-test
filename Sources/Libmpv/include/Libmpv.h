#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

//! Project version number for Libmpv.
FOUNDATION_EXPORT double LibmpvVersionNumber;

//! Project version string for Libmpv.
FOUNDATION_EXPORT const unsigned char LibmpvVersionString[];

// mpv headers
#import <mpv/client.h>
#import <mpv/render.h>
#import <mpv/render_gl.h>

// Additional dependencies
#import <zlib.h>
#import <bzlib.h>