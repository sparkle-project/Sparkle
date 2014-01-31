// Header that shouldn't be included in anything but the Sparkle finish_installation tool
//	because it includes files also used in EyeTV, but doesn't need to be thread safe
//	as it's a single-threaded process anyway.

#ifndef EYETV
#define EYETV		0
#endif
#ifndef __TOAST__
#define __TOAST__	0
#endif
#ifndef TURBO
#define TURBO		0
#endif

#if !EYETV && !__TOAST__ && !TURBO

#define ThreadSafePreferences_CopyAppValue	CFPreferencesCopyAppValue
#define ThreadSafePreferences_SetValue		CFPreferencesSetValue
#define ThreadSafePreferences_Synchronize	CFPreferencesSynchronize

#else

#error This header shouldn't be included here!

#endif
