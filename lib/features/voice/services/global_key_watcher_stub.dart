/// No system-wide keys on this platform (the web).
const bool globalKeysSupported = false;

bool isVirtualKeyDown(int virtualKey) => false;

int? virtualKeyFor(int usbHidUsage) => null;
