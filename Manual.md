# GeoMotionGen 1.0

## Introduction

The GeoMotionGen 1.0 is a frame-generating/interpolating technique that, given only geometric per-pixel motion from latest frame to its previous frame, generates interpolating frames in between. Given that the algorithm ditched the need for optical flow, it's particularly suitable for scenarios where computational cost is critical. To achieve maximum flexibility, GeoMotionGen also supports interpolating at any point between the previous and the current frame, making it possible for the swap chain to present multiple frames between two actual rendered frames. An insertion point for hardware-generated optical flow from video codecs is also prepared, in the event of GPU vendors wanting it as a backup criterion when it comes to estimating pixel movements.

The input of the algorithm consists of only the depth and color of the previous frame, the current frame, as well as the per-pixel geometric motion vector from this frame to previous frame, making it very easy to be integrated into games and other 3D applications, as well as popular game engines. There's a GeoMotionGen Unreal Engine plugin repo actively maintained for Unreal Engine 5.0.3 and beyond.

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

To make an educated guess for each of the occluded areas and how they move from the previous frame to the current frame, we need to construct a pyramid of geometric vectors and fill the holes with elements from coarser layers. We call this a push-pull process, where "pulling" stands for moving up in the pyramid, constructing a coarser layer from its finer layer, and "pushing" stands for moving down in the pyramid, pushing the coarser elements into the finer layer where reprojection failed. This way we dissipate the reprojected geometric motion vector wider, and fill the holes too.

Namely, for each finer `2x2` block of pixels containing geometric motion vectors, we downsample it by averaging all the valid elements (i.e. written in reprojection phase). If all 4 pixels are still `UnwrittenPackedClearValue`, we leave the downsampled pixel to `UnwrittenPackedClearValue` as well. Write the downsampled pixel to the coarser layer and repeat until all 7 layers of pyramid are fulfilled.

Once the pyramid is ready, move top-down, starting from the coarsest level to its finer level. If a pixel in the finer level is already marked as written, either natively or from downsampled pyramid layer, we keep that written value untouched in the finer layer. If not, we fill the unwritten pixel with the coarser level pixel, be it unwritten or not, but still mark it as unwritten for the curious frame. This way we dissipate the motion vector around further, and the final merging pass knows that although the pixel reprojected from the current frame is no-longer usable due to disocclusion, it can still reverse the inpainted, dissipated motion vector and fetch a pixel from the previous frame instead.

Ultimately, using this filled geometric vector, we can backtrace to the current frame and fetch a pixel to fill the intermediate frame when the reprojected geometric motion vector is marked unwritten. For those areas that are marked unwritten, we simply reverse the motion and trace forward to the previous frame, and grab a pixel there. This way, we can merge the previous frame and the current frame and fuse into one intermediate frame.

## Passes

To generate intermediate frames, GeoMotionGen uses the process below to deduct the middle ground between two consecutive frames:

1. Clear
Clear the disocclusion mask textures for both X and Y directions, and set every texel to `UnwrittenPackedClearValue`. For each interpolated frame, we need to clear the two buffers first before conducting any operations because we tell if the reprojection has succeeded by inspecting if it was written or not. Part of the geometry invisible (occluded) in the current frame might become visible in the interpolated frame. To decide which previously invisible pixels become visible when this backtracking happens, we need to maintain two buffers for reprojected geometric motion vectors simutaneously. The criterion is quite simple: Those pixels that are written in the reprojection phase are still visible, and those without anyone filling them, themselves included, are the pixels that become visible in the interpolated frame.

2. Normalize
Convert the screen space geometric motion in pixels into normalized NDC space, ranging [0, 1]. Since the definition for geometric motion vector varies from platform to platform, we need to convert them into our definition: Motion is per-pixel, normalized within [0, 1] range like it's a uv, in NDC coordinates, and points from the current frame geometry to that of the previous frame. The implementation of this pass varies from platform to platform.

3. Reproject
Reproject the geometric motion vector that points from the current frame geometry to the previous frame geometry to the middle ground position, with depth awareness. Since multiple pixels might end up in the same position, we need to determine which pixel is the closest one to the camera, and pick exactly the one. To avoid race condition, we pack depth and indices into a 32bit integer, with first 19 bits being the depth, and last 13 bits being the index. The first 7 bits of the 19 bits being the exponential part, and the last 12 bits of the 19 bits being the mantissa of the floating point number of the depth. Under this customized 19 bit floating point format, we guarantee that depth comparison is maintained even if we reinterpret the binaries as integers. By packing both depth and index into a 32bit integer representation, we can safely write the closest one to the reprojection buffer using `atomicmax` without worrying about race conditions.

Therefore, given that `$2**13=8192$`, our algorithm supports up to `$8192*8192$` resolution.

4. Merge
In the reprojection pass we pack the depth and the index of the motion vector together, not the depth and the motion vector itself, mainly to save bandwidth on the atomic operations, given that `atomic64` operations are only available to DX12 enabled devices. This merging pass extracts the indices from the 32 bit packed values, and reads the motion vector from the unprojected motion texture.

After this pass, we have the reprojected motion vectors.

5. Pull
Build the 7-layer pyramid from the reprojected motion vector full of holes and reprojection failures, starting from the finest layer and working all the way to the top. This process consists of 6 passes, and each pass takes in the finer reprojected motion, averages the valid, written motions within a `2x2` block, and writes the average to the coarser layer, essentially doing mipmapping. If none of the 4 pixels in the `2x2` were written, we mark the coarser layer's pixel as unwritten as well.

6. Push
From the mipmap pyramid, we push the coarser layer's pixels into the finer layer, if the finer layer's pixel is still unwritten. This process consists of 6 passes as well, but this time top-down, starting from the coarsest layer.

After these passes we finally obtained the inpainted motion vectors, with occlusion masks. Those that are marked written are the pixels that are visible in both the generated frame and the current frame, and those that are marked unwritten would be the ones unseen in the current frame but become visible in the generated frame, but with a geometric motion vector as well.

7. Resolution.
At long last we resolve the generation process by fusing the two frames together. For each pixel, if the geometric vector is marked written, we do a backtrace along the geometric motion vector and fetch the current frame's pixel. Otherwise we read the geometric motion anyway because it's the guesswork of the previous push-pull inpainting passes, revert the motion direction, and fast-forward along the geometric motion vector, and fetch the previous frame's pixel.

By doing this fusion, we have generated an interpolated frame from the current frame and the previous frame.

## Limitations

Since there's no optical flow input, there's no way the algorithm can detect non-geometrical movements, such as shadows, reflections, and pure texture changes without explicit geometry movements. This will be remedied by adding hardware-generated optical flow from video encoders to the algorithm's input, and the algorithm will treat the optical flow as a secondary criterion for pixel movements. One final per-pixel decision between geometric motion and optical flow will be made depending on how well the two traced pixels in the previous and the current frames match each other, and the one that produces more matching pixel pairs will be chosen to fuse the two frames together. To remedy this artifact without introducing dedicated hardware, draw the screen-space reflections and other post-processing passes after the frame is interpolated, and provide the algorithm with input frames that haven't undergone screen-space post-processing yet.

The mipmap pyramid is limited to 7 layers, limiting the maximum dissipating distance of the geometric motion vector to 512 pixels. If the geometrical distance between the previous frame geometry and the interpolated frame is greater than 512 pixels, some of the geometry would simply refuse to be warped to the intermediate position, causing tearing artifacts in the final image.
