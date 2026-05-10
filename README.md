LPR is a custom system injected into Unity 6's URP designed to render scenes with a crisp pixel art aesthetic. Since I built this specifically for mobile devices, optimization wasn't just a "nice-to-have"—it was the core mission. Traditional downscaling was off the table for this project, so I had to get creative.
### Final Packed Deferred Scene View
<img width="1649" height="882" alt="SceneView" src="https://github.com/user-attachments/assets/35d19cc8-d4b6-4d5e-9008-ab1f0567d8f3" />
  
### Final Packed Deferred Game View
<img width="1437" height="892" alt="GameView" src="https://github.com/user-attachments/assets/21b9ecf3-b7db-477b-8fea-f7381a70d506" />
Here’s a look at the journey, the logic behind my decisions, and the technical hurdles I crossed.
  ## The Cel-Shading Experiment

I started by tossing Unity’s standard PBR lighting aside and writing my own Cel-shading calculations.

  - The Plan: It felt more "correct" for a pixel art style and I hoped it would lighten the fragment shader load by simplifying the math.

  - The Reality: Looking back, this didn't actually provide a performance boost. Since the rendering happens at roughly 20% of the screen resolution, the fragment shader is already quite light. Saving a few ALU cycles per pixel doesn't make a noticeable difference when your pixel count is that low!

  ## The Camera Dilemma & The Pivot

Even with the custom lighting, I was still rendering at full resolution. I tried tweaking the render scale (even with Nearest Neighbor filtering), but it just didn't give me the look I wanted.

My first attempt at a solution was using two cameras:

  - One camera rendered the scene to a low-res, point-filtered Render Texture (RT).

  - The second camera simply sampled that texture and pushed it to the screen.

This allowed for post-processing effects, but I hit a wall: Depth. Most effects (like outlines) need depth info. Enabling "Depth Texture" in URP kills mobile performance, so I had to find a "cheaper" way. I swapped the standard RGBA format for a uint R32 format. I didn't need millions of colors for pixel art, so I compressed the color data into 15-bit HSV. This left me with:

  - 16 bits for Depth info.

  - 1 bit as a flag to toggle the Outline effect.

  ## Moving to Renderer Features

While the two-camera system worked, it felt unprofessional and rigid. It wasn't scalable or easy to develop further. I realized I needed a better architecture.

I considered writing a full custom Scriptable Render Pipeline (SRP), but due to time constraints and the need for fast prototyping, I decided to stay within URP. My solution was to build a pipeline that is injected into URP but acts independently. It ignores default URP passes, does everything in custom passes, writes to my own RTs, and finally blits the result onto the URP target.

I wrote 4 different Renderer Feature systems to test different mobile optimizations:

  - Low-Res Forward: A clean injection that renders at low resolution for a massive performance jump.

  - Packed Forward: An evolution that packs color and depth together, saving bandwidth during post-processing.

  - Deferred & Packed Deferred: Standard and bit-packed variations of a deferred rendering structure to minimize memory footprint.

 ### Packed Deferred Render Graph
<img width="1100" height="660" alt="PackedDeferredRenderGraph" src="https://github.com/user-attachments/assets/929366a2-65f8-482c-b651-97d45e5b5de6" />

  ## The "Outline" Trade-off

In my early versions, I tried to merge the Opaque and Opaque Post-Process passes using Framebuffer Fetch to keep data in tile memory (avoiding VRAM writes). It was incredibly fast.

However, this meant the Outline effect had to stay in the Global Post-Process phase, which runs at full screen resolution. Calculating complex outlines at 1080p/4K was much more expensive than just breaking the pass. I ultimately decided to move the Outline effect into the low-res Opaque pass. Even though I lost the "pass merging" optimization, reducing the number of pixels the outline had to calculate for resulted in a much higher overall frame rate.
