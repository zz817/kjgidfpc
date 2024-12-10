The repo is a offline demo.

Input resource details:
ClipInfo:
Must be binary file, layout is
struct ClipInfo {
  float prevClipToClip[16];
  float clipToPrevClip[16];
};

ColorInput:
Must be a png file, and has four channel.

Depth:
Must be binary file, the default format is DXGI_FORMAT_R24_UNORM_X8_TYPELESS

MotionVector:
Must be binary file, the default format is DXGI_FORMAT_R16G16_FLOAT

Output resource details:
ColorOutput:
It will be a png file.

All the needed file should locate same directory with exe. Such as:
sample.exe
ClipInfo\clipinfo_x.bin
ColorInput\colorinput_x.png
Depth\depth_x.bin
MotionVector\motionvector_x.bin
ColorOutput\colorout_x.png

x means frame index.

You can config depth/motion vector format by create a config.json file.
The json like:
{
    "DepthFormat" : 46,  DXGI_FORMAT
    "MevcFormat" : 34,   DXGI_FORMAT
    "BeginFrameId" : 0,
    "EndFrameId" : 1,
    "InterpolatedFrames" : 2
}

The project will auto-gen dxbc file to exe directory, it means you can modify the hlsl file and build project, the shader will auto update.
Also you can wirte only hlsl file and compile it to dxbc and then set the dxbc file to exe directory.

Test data link: https://drive.google.com/file/d/12dMkKSQmnnrl-C85cgQOy8QjKece2qQu/view?usp=drive_link

-----------------------------------------------------------------------------------------------------------------------

The renderdoc link: https://drive.google.com/file/d/1ijA_CM6_lyFyBhIFLavr905KQOyNW0Vr/view?usp=drive_link

How to use?
This version render doc add four environment variable keys：

StartDrawId, begin with 0, per draw call increament 1, default is UINT_MAX

EndDrawId,default is UINT_MAX

StartDispatchId, begin with 0, per dispatch call increament 1,default is UINT_MAX

EndDispatchId,default is UINT_MAX