# GeoMotionGen 1.0

## Introduction

The GeoMotionGen 1.0 is a frame-generating/interpolating technique that, given only geometric per-pixel motion from latest frame to its previous frame, generates interpolating frames in between. Given that the algorithm ditched the need for optical flow, it's particularly suitable for scenarios where computational cost is critical.

The input of the algorithm consists of only the previous frame, the current frame, and the per-pixel geometric motion vectors, making it very easy to be integrated into games and other 3D applications, as well as popular game engines. There's a GeoMotionGen Unreal Engine plugin repo maintained actively for Unreal Engine 5.0.3 and beyond.

