#ifndef __PREVIEWVIDEO_H
#define __PREVIEWVIDEO_H

#import <Foundation/Foundation.h>
#include <opencv/cv.h>
#include <opencv/highgui.h>
#include <stdio.h>

class previewVideo{

public:

	bool isRunning;
	previewVideo(NSLock *lock);
	~previewVideo();
	bool setFrame(IplImage * frame, uint64_t frameNumber);
	bool stop();

	bool ProcessNextPreview();

private:

	static DWORD previewThread(void* param);
	bool Lock();
	bool Unlock();
	NSLock *lock;
	id _previewThread;
	NSLock *previewThreadReadySignal;
	IplImage * frame, * frameCopy;
	size_t frameSize;
	uint64_t frameNumber, lastFrameNumber;
};


#endif