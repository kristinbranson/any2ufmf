#include <shobjidl.h>     // for IFileDialogEvents and IFileDialogControlEvents
#include <objbase.h>      // For COM headers

class CDialogEventHandler;

HRESULT CDialogEventHandler_CreateInstance(REFIID riid, void **ppv);