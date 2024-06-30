# GeoMotionGen 1.0

## Introduction

The GeoMotionGen 1.0 is a frame-generating/interpolating technique that, given only geometric per-pixel motion from latest frame to its previous frame, generates interpolating frames in between. Given that the algorithm ditched the need for optical flow, it's particularly suitable for scenarios where computational cost is critical.

The input of the algorithm consists of only the previous frame, the current frame, and the per-pixel geometric motion vectors, making it very easy to be intergrated into games and other 3D applications, as well as popular game engines. There's a GeoMotionGen Unreal Engine plugin repo maintained actively for Unreal Engine 5.0.3 and beyond.

## Requirements

The algorithm is implemented with DirectX compute shader and relies heavily on `atomicmax` operations. Device with DX11 or higher compatibilities is required.

## Algorithm

The core of the algorithm is essentially based on depth-aware reprojection along geometric motion vectors.

To generate an interpolated frame in between two consecutive frames based on the geometric motions only, one core question arises naturally: For each pixel in the intermediate interpolated frame, where would its color come from? Is it the backtraced current frame pixel, or the fast-forwarded previous frame, or neither? Depth-aware reprojection answers the question by reprojecting current geometric motion to the middle ground, a.k.a. the interpolated frame's position along the geometric motion itself. If multiple pixels landed in the same middle ground pixel, pick the one closest to the camera because the other ones would simply be occluded. Once the reprojection phase is complete, we end up with a geometric motion vector reprojected to the intermediate frame's position, with patches of pixels remain unwritten. The unwritten pixels indicate that these pixels left their positions by reprojecting backwards, but no other pixels filled their positions, flagging a disocclusion happening. Do the same for the previous frame, and we have a disocclusion map of pixels for us to decide which pixels to use when it comes to merging two warped frames into one intermediate frame.

To put it into actual formulas,

Let `$p_n(x, y)$` denote pixels from the newer (current) frame, and `$m_n(x, y)$` denote the geometric motion vector pointing from the current frame to the previous frame. Similarly, let `$d_n(x, y)$` denote the depth of the current pixel.

From `$(x, y)$`, backtrace the middle ground position to `$(x, y) - 0.5 m_n(x, y)$`. Write the combination of the depth and the geometric motion vector's starting location indices to the reprojection buffer. Namely, we compress `$d_n(x, y)$` into a 19-bit floating point representation, and pack it with another 13 bits of integer `$(x, y)$` indices to form a 32bit binary, which is then written with `atomicmax()` to the texel indexed by `$(x, y) - 0.5 m_n(x, y)$` in the texture. This way we guarantee that even under parallelism we write the closest reprojected pixel to the backtraced position, given that floating point numbers increase monotonously when the underlying binary increases.

Once we have the reprojected buffer, we can derive both the reprojected motion vector needed by the intermediate frame to fetch a pixel from the current frame, and the disocclusion mask: If a pixel is written, it's not occluded in the intermediate frame; If a pixel is left untouched, it's the pop-up pixel that suddenly becomes visible that was disoccluded in the previous frame, therefore not to be trusted. We need to grab the pixels from the previous frame instead of the current frame because these pixels are occluded and, consequently, unknown to the current frame.

However, we are unable to use the same fashion to warp the previous frame to the middle ground, and determine the disocclusion from the previous frame to the middle ground, given that we don't have the geometric vector from the previous frame to the current frame, which is not just the inverse of the motion vector we have right now. What further complicates things is that, the reprojection is not a one-to-one mapping from the current frame to the intermediate frame. If the reprojection is being magnified while backtraced (i.e. the scene is getting zoomed out with time going forward) there would be multiple pixels in the middle ground mapped to just one pixel in the current (newer) frame. A lot of guesswork is involved in this process, which we call inpainting.

To make an educated guess for each of the occluded areas and how they move from the previous frame to the current frame, we need to construct a pyramid of 

## Passes

To generate intermediate frames, GeoMotionGen uses the process below to deduct the middle ground between two consecutive frames:

1. Clear the disocclusion mask textures and set every texel to `UnwrittenPackedClearValue`.

2. Convert the screen space geometric motion in pixels into normalized NDC space, ranging [0, 1].

3. Reproject the geometric motion vector that points from the current frame geometry to the previous frame geometry to the middle ground position, with depth awareness

4. Resolve the geometric vectors at the middle ground position, and mark the disoccluded areas still with `UnwrittenPackedClearValue` as unknown.

5. Inpaint the geometric motion vector and do some guesswork to the disoccluded areas by building a pyramid and fill the unknown disoccluded areas with push-pulled motion vectors.

6. Fetch the pixels from both frames using the inpainted geometric motion vector and merge them into a new frame.

## Detailed explanation of the passes

### Clear

Part of the geometry invisible (occluded) in the current frame might become visible in the interpolated frame. To decide which previously invisible pixels become visible when this backtracking happens, we need to maintain two buffers for reprojected geometric motion vectors. The criterion is quite simple: Those pixels that are written in reprojection phase are still visible 
