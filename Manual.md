# GeoMotionGen 1.0

## Introduction

The GeoMotionGen 1.0 is a frame-generating/interpolating technique that, given only geometric per-pixel motion from latest frame to its previous frame, generates interpolating frames in between. Given that the algorithm ditched the need for optical flow, it's particularly suitable for scenarios where computational cost is critical.

The input of the algorithm consists of only the previous frame, the current frame, and the per-pixel geometric motion vectors, making it very easy to be integrated into games and other 3D applications, as well as popular game engines. There's a GeoMotionGen Unreal Engine plugin repo maintained actively for Unreal Engine 5.0.3 and beyond.

## Requirements

The algorithm is implemented with DirectX compute shader and relies heavily on `atomicmax` operations. Device with DX11 or higher compatibilities is required.

## Passes

To generate intermediate frames, GeoMotionGen uses the process below to deduct the middle ground between two consecutive frames:

1. Clear the disocclusion mask textures and set every texel to `UnwrittenPackedClearValue`.

2. Convert the screen space geometric motion in pixels into normalized NDC space, ranging [0, 1].

3. Reproject the geometric motion vector that points from current frame geometry to previous frame geometry to the middle ground position, with depth awareness

4. Resolve the geometric vectors at the middle ground position, and mark the disoccluded areas still with `UnwrittenPackedClearValue` as unknown.

5. Inpaint the geometric motion vector and do some guesswork to the disoccluded areas by building a pyramid and fill the unknown disoccluded areas with push-pulled motion vectors.

6. Fetch the pixels from both frames using the inpainted geometric motion vector and merge them into a new frame.

