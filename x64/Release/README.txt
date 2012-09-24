any2ufmf

Kristin Branson
bransonk@janelia.hhmi.org
2012-07-13

any2ufmf reads in videos of various formats and outputs a compressed UFMF (micro-fly movie format) video. I'm not sure what kinds of videos it reads -- whatever OpenCV reads. It has worked on uncompressed AVIs (BI_RGB Raw Bitmap), motion JPEG AVIs, and H.264 Quicktime MOV files. 

I wrote this program when debugging my video data capture code. Its interface is rather bare, but it may be useful to someone. 

Requirements: 
Windows 64 Operating System
Microsoft Visual C++ 2010 Redistributable Package, available for download here:
http://www.microsoft.com/en-us/download/details.aspx?displaylang=en&id=14632

Contents:

Binary any2ufmf.exe. 
Example compression parameters file ufmfCompressionParams.txt. 
README.txt
any2ufmf_interface_screencap.png

1. Run any2ufmf.exe
2. When prompted, enter the full path to the video to the read in. 
3. When prompted, enter the full path to the UFMF output file. 
4. When prompted, enter the full path to the video compression parmeters. 
(See any2ufmf_interface_screencap.png for an example.)
5. A preview window will pop up showing the current frame being read, and some output will appear in the terminal indicating what the compressor is doing. 
