#include "cv.h"
#include "highgui.h"
#include <stdio.h>
#include "ufmfWriter.h"
#include "previewVideo.h"

bool ChooseFile(char aviFileName[],const char[]);

int main(int argc, char * argv[]){


	double timestamp;
	double frameRate = 1.0/30.0;
	char aviFileName[260];
	char ufmfFileName[260];
	char ufmfParamsFileName[260];
	bool interactiveMode = argc <= 3;

	// first argument is the input AVI
	if(argc > 1){
		strcpy(aviFileName,argv[1]);
		fprintf(stdout,"Input AVI file = %s\n",aviFileName);
	}
	else{
		ChooseFile(aviFileName,"AVI");
	}

	// input avi
	CvCapture* capture = cvCaptureFromAVI(aviFileName);
	if(capture==NULL){
		fprintf(stderr,"Error reading AVI %s. Exiting.\n",aviFileName);
		if(interactiveMode){
			fprintf(stderr,"Hit enter to exit\n");
			getc(stdin);
		}
		return 1;
	}

	// output ufmf
	if(argc > 2){
		strcpy(ufmfFileName,argv[2]);
		fprintf(stdout,"Output UFMF file = %s\n",ufmfFileName);
	}
	else{
		ChooseFile(ufmfFileName,"UFMF");
	}

	// parameters
	if(argc > 3){
		strcpy(ufmfParamsFileName,argv[3]);
		fprintf(stdout,"UFMF Compression Parameters file = %s\n",ufmfParamsFileName);
	}
	else{
		ChooseFile(ufmfParamsFileName,"UFMF Compression Parameters");
	}

	// get avi frame size
	cvQueryFrame(capture); // this call is necessary to get correct capture properties
	unsigned __int32 frameH = (unsigned __int32) cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_HEIGHT);
	unsigned __int32 frameW = (unsigned __int32) cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_WIDTH);
	double nFrames = cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_COUNT);
	fprintf(stderr,"Number of frames in the video: %f\n",nFrames);

	// log file
	//FILE * logFID = fopen("C:\\Code\\imaq\\any2ufmf\\out\\log.txt","w");
	FILE * logFID = stderr;

	// output ufmf
	ufmfWriter * writer = new ufmfWriter(ufmfFileName, frameW, frameH, logFID, ufmfParamsFileName);

	// start preview thread
	HANDLE lock = CreateSemaphore(NULL,1,1,NULL);
	previewVideo * preview = new previewVideo(lock);

	// start writing
	if(!writer->startWrite()){
		fprintf(stderr,"Error starting write\n");
		if(interactiveMode){
			fprintf(stderr,"Hit enter to exit\n");
			getc(stdin);
		}
		return 1;
	}

	IplImage * frame = NULL;
	unsigned __int64 frameNumber;
	IplImage * frameWrite = NULL;
	IplImage * grayFrame = cvCreateImage(cvSize(frameW,frameH),IPL_DEPTH_8U,1);

	fprintf(stderr,"Hit esc to stop playing\n");
	bool DEBUGFAST = false;
	for(frameNumber = 0, timestamp = 0; ; timestamp += frameRate){

		if(DEBUGFAST && frameNumber >= 3000)
			break;

		if((frameNumber % 100) == 0){
			fprintf(stderr,"** frame %lu\n",frameNumber);
		}

		if(!DEBUGFAST && (WaitForSingleObject(lock, MAXWAITTIMEMS) != WAIT_OBJECT_0)) { 
			fprintf(stderr,"Error waiting for preview thread to unlock\n");
			break;
		}
		if(!DEBUGFAST || (frame == NULL))
			frame = cvQueryFrame(capture);
		frameNumber++;
		if(!DEBUGFAST) ReleaseSemaphore(lock,1,NULL);
		if(!frame){
			fprintf(stderr,"Last frame read = %d\n",frameNumber);
			break;
		}
		if(!DEBUGFAST && !preview->setFrame(frame,frameNumber)){
			break;
		}
		
		if(!DEBUGFAST || frameWrite == NULL){
			if(frame->nChannels > 1){
				cvCvtColor(frame,grayFrame,CV_RGB2GRAY);
				frameWrite = grayFrame;
			}
			else{
				frameWrite = frame;
			}
		}
		if(!writer->addFrame((unsigned char*) frameWrite->imageData,timestamp)){
			fprintf(stderr,"Error adding frame %d\n",frameNumber);
			break;
		}

	}

	if(!writer->stopWrite()){
		fprintf(stderr,"Error stopping writing\n");
		if(interactiveMode){
			fprintf(stderr,"Hit enter to exit\n");
			getc(stdin);
		}
		return 1;
	}

	if(!preview->stop()){
		fprintf(stderr,"Error waiting for preview thread to unlock\n");
	}

	// clean up
	if(preview != NULL){
		delete preview;
		preview = NULL;
	}
	if(lock){
		CloseHandle(lock);
		lock = NULL;
	}
	if(capture != NULL){
		cvReleaseCapture(&capture);
		capture = NULL;
		frame = NULL;
	}
	if(grayFrame != NULL){
		cvReleaseImage(&grayFrame);
		grayFrame = NULL;
	}
	if(writer != NULL){
		delete writer;
	}

	if(interactiveMode){
		fprintf(stderr,"Hit enter to exit\n");
		getc(stdin);
	}

	return 0;
}


bool ChooseFile(char aviFileName[], const char fileType[]){
	fprintf(stderr,"Enter the full path to the %s file: ",fileType);
	gets(aviFileName);
	return 0;
}
