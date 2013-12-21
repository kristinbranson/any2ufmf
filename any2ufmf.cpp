#include <stdio.h>
#include "cv.h"
#include "highgui.h"
#include "ufmfWriter.h"
#include "previewVideo.h"
#include <shobjidl.h>     // for IFileDialogEvents and IFileDialogControlEvents
#include <objbase.h>      // For COM headers

typedef enum {
    DialogTypeInput,
    DialogTypeOutput
} DialogType;

bool ChooseFile(char fileName[], const COMDLG_FILTERSPEC filterSpec[], int nFilters, DialogType dialogType);

int main(int argc, char * argv[])
{
	bool interactiveMode = argc <= 3;
    bool fileChoiceSuccess = true;;

    // first argument is the input AVI
	char aviFileName[512];
	if(argc > 1){
		strcpy(aviFileName,argv[1]);
        fprintf(stdout,"Input AVI file = %s\n",aviFileName);
	}
	else{
        const COMDLG_FILTERSPEC aviTypes[] =
        {
            {L"Audio-video Interleave Files (*.avi)",   L"*.avi"},
            {L"All Files (*.*)",    					L"*.*"}
        };
		fileChoiceSuccess = ChooseFile(aviFileName,aviTypes, ARRAYSIZE(aviTypes), DialogTypeInput);
	}

    // test input file
    if( !fileChoiceSuccess || strlen( aviFileName ) == 0 ) {
        if( !interactiveMode )
            fprintf( stderr, "Empty input filename specified. Aborting.\n" );
        return 1;
    }

	// input avi
    CvCapture* capture = cvCaptureFromAVI(aviFileName);
	if(capture==NULL){
		if(interactiveMode){
            MessageBox( NULL, "Error reading AVI. Exiting.", NULL, MB_OK );
		}
        else {
            fprintf(stderr,"Error reading AVI %s. Exiting.\n",aviFileName);
        }
		return 1;
	}

	// output ufmf
	char ufmfFileName[512];
	if(argc > 2){
		strcpy(ufmfFileName,argv[2]);
        fprintf(stdout,"Output UFMF file = %s\n",ufmfFileName);
	}
	else{
        const COMDLG_FILTERSPEC ufmfTypes[] =
        {
            {L"Micro Fly Movie Format Files (*.ufmf)",  L"*.ufmf"},
            {L"All Files (*.*)",    					L"*.*"}
        };
		fileChoiceSuccess = ChooseFile(ufmfFileName,ufmfTypes, ARRAYSIZE(ufmfTypes), DialogTypeOutput);
	}

    // test output file
    if( !fileChoiceSuccess || strlen( ufmfFileName ) == 0 ) {
        if( !interactiveMode )
            fprintf( stderr, "Empty output filename specified. Aborting.\n" );
        return 1;
    }

    FILE *fp = fopen( ufmfFileName, "w" );
    if( fp == NULL ) {
        if(interactiveMode){
            MessageBox( NULL, "Error opening output file. Exiting.", NULL, MB_OK );
		}
        else {
            fprintf(stderr,"Error opening output file\n");
        }
		return 1;
    }
    fclose( fp );

	// parameters
	char ufmfParamsFileName[512];
	if(argc > 3){
		strcpy(ufmfParamsFileName,argv[3]);
		fprintf(stdout,"UFMF Compression Parameters file = %s\n",ufmfParamsFileName);
	}
	else{
        int choice = MessageBox( NULL, "Select a custom parameters file?", "Specify parameters?", MB_YESNO );
        if( choice == IDYES ) {
            const COMDLG_FILTERSPEC ufmfParamTypes[] =
            {
                {L"Text Files (*.txt)", L"*.txt"},
                {L"All Files (*.*)",    L"*.*"}
            };
		    ChooseFile(ufmfParamsFileName,ufmfParamTypes, ARRAYSIZE(ufmfParamTypes), DialogTypeInput);
        }
        else
            ufmfParamsFileName[0] = '\0';
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
	if(!writer->startWrite()){
		if(interactiveMode){
            MessageBox( NULL, "Error initializing uFMF writer. Exiting.", NULL, MB_OK );
		}
        else {
            fprintf(stderr,"Error starting write\n");
        }
		return 1;
	}

	// start preview thread
	HANDLE lock = CreateSemaphore(NULL,1,1,NULL);
	previewVideo * preview = new previewVideo(lock);

    IplImage * frame = NULL;
	unsigned __int64 frameNumber;
	IplImage * frameWrite = NULL;
	IplImage * grayFrame = cvCreateImage(cvSize(frameW,frameH),IPL_DEPTH_8U,1);

    double timestamp;
	double frameRate = 1.0/30.0;

	fprintf(stderr,"Hit esc to stop playing\n");
	bool DEBUGFAST = false;
	for(frameNumber = 0, timestamp = 0.; ; frameNumber++, timestamp += frameRate){

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
		//frameNumber++;
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


bool ChooseFile(char fileName[], const COMDLG_FILTERSPEC filterSpec[], int nFilters, DialogType dialogType)
{
	HRESULT hr;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (SUCCEEDED(hr))
    {
	    IFileDialog *fileDialog = NULL;
        if( dialogType == DialogTypeInput ) {
            hr = CoCreateInstance(CLSID_FileOpenDialog, 
                                  NULL, 
                                  CLSCTX_INPROC_SERVER, 
                                  IID_PPV_ARGS(&fileDialog));
        } else {
            hr = CoCreateInstance(CLSID_FileSaveDialog, 
                                  NULL, 
                                  CLSCTX_INPROC_SERVER, 
                                  IID_PPV_ARGS(&fileDialog));
        }
        if (SUCCEEDED(hr))
	    {
            // Set the options on the dialog.
            DWORD dwFlags;

            // Before setting, always get the options first in order 
            // not to override existing options.
            hr = fileDialog->GetOptions(&dwFlags);
            if (SUCCEEDED(hr))
            {
                // In this case, get shell items only for file system items.
                hr = fileDialog->SetOptions(dwFlags | FOS_FORCEFILESYSTEM);
                if (SUCCEEDED(hr))
                {
                    // Set the file types to display only. 
                    // Notice that this is a 1-based array.
                    hr = fileDialog->SetFileTypes(nFilters, filterSpec);
                    if (SUCCEEDED(hr))
                    {
                        // Set the selected file type index to the first filter
                        hr = fileDialog->SetFileTypeIndex(1);
                        if (SUCCEEDED(hr))
                        {
                            // Show the dialog
                            hr = fileDialog->Show(NULL);
                            if (SUCCEEDED(hr))
                            {
                                // Obtain the result once the user clicks 
                                // the 'Open' button.
                                // The result is an IShellItem object.
                                IShellItem *psiResult;
                                hr = fileDialog->GetResult(&psiResult);
                                if (SUCCEEDED(hr))
                                {
                                    PWSTR pszFilePath = NULL;
                                    hr = psiResult->GetDisplayName(SIGDN_FILESYSPATH, &pszFilePath);

                                    if (SUCCEEDED(hr))
                                    {
                                        WideCharToMultiByte( CP_ACP,
                                                                WC_COMPOSITECHECK,
                                                                pszFilePath,
                                                                -1,
                                                                fileName,
                                                                512,
                                                                NULL,
                                                                NULL );
                                        CoTaskMemFree(pszFilePath);
                                    }
                                    else fprintf( stderr, "failure 9\n" );
                                    psiResult->Release();
                                }
                                else fprintf( stderr, "failure 8\n" );
                            }
                            else fprintf( stderr, "failure 7\n" ); // user pressed "cancel"
                        }
                        else fprintf( stderr, "failure 6\n" );
                    }
                    else fprintf( stderr, "failure 5\n" );
                }
                else fprintf( stderr, "failure 4\n" );
            }
            else fprintf( stderr, "failure 3\n" );
		    fileDialog->Release();
	    }
        else fprintf( stderr, "failure 2\n" );
        CoUninitialize();
    }
    else fprintf( stderr, "failure 1\n" );

    if( FAILED( hr ) ) {
        *fileName = 0;
    }

	return SUCCEEDED( hr );
}
