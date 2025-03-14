/*=============================================================================
    TFAA (1.1.2)
    Temporal Filter Anti-Aliasing Shader
    First published 2022 - Copyright, Jakob Wapenhensch
    License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/)
    https://creativecommons.org/licenses/by-nc/4.0/legalcode
=============================================================================*/

#include "ReShade.fxh"

/*=============================================================================
    Preprocessor Settings
=============================================================================*/

// Uniform variable to access the frame time.
uniform float frametime < source = "frametime"; >;


/*=============================================================================
    UI Uniforms
=============================================================================*/

/**
 * @brief Slider controlling the strength of the temporal filter.
 */
uniform float UI_TEMPORAL_FILTER_STRENGTH <
    ui_type    = "slider";
    ui_min     = 0.0; 
    ui_max     = 1.0; 
    ui_step    = 0.01;
    ui_label   = "Temporal Filter Strength";
    ui_category= "Temporal Filter";
    ui_tooltip = "";
> = 0.5;

/**
 * @brief Slider controlling the amount of adaptive sharpening.
 */
uniform float UI_POST_SHARPEN <
    ui_type    = "slider";
    ui_min     = 0.0; 
    ui_max     = 1.0; 
    ui_step    = 0.01;
    ui_label   = "Adaptive Sharpening";
    ui_category= "Temporal Filter";
    ui_tooltip = "";
> = 0.5;

// uniform int UI_COLOR_CONVERSION_MODE <
//     ui_type = "combo";
//     ui_label = "Color Conversion Mode";
//     ui_items = "RGB\0YCbCr\0";
//     ui_tooltip = "Select the color conversion method.";
//     ui_category = "";
// > = 1;

#define UI_COLOR_CONVERSION_MODE 1

// uniform int UI_DEBUG_MODE <
// 	ui_type = "combo";
//     ui_label = "DEBUG MODE";
// 	ui_items = "None\0Weight\0Sharp\0Occlusion\0";
// 	ui_tooltip = "";
//     ui_category = "";
// > = 0;


/*=============================================================================
    Textures & Samplers
=============================================================================*/

// Texture and sampler for depth input.
texture texDepthIn : DEPTH;
sampler smpDepthIn { 
    Texture = texDepthIn; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Texture and sampler for the current frame's color.
texture texInCur : COLOR;
sampler smpInCur { 
    Texture   = texInCur; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Backup texture for the current frame's color.
texture texInCurBackup < pooled = true; > { 
    Width   = BUFFER_WIDTH; 
    Height  = BUFFER_HEIGHT; 
    Format  = RGBA8; 
};

sampler smpInCurBackup { 
    Texture   = texInCurBackup; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Texture for storing the exponential frame buffer.
texture texExpColor < pooled = true; > { 
    Width   = BUFFER_WIDTH; 
    Height  = BUFFER_HEIGHT; 
    Format  = RGBA16F; 
};

sampler smpExpColor { 
    Texture   = texExpColor; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Backup texture for the exponential frame buffer.
texture texExpColorBackup < pooled = true; > { 
    Width   = BUFFER_WIDTH; 
    Height  = BUFFER_HEIGHT; 
    Format  = RGBA16F; 
};

sampler smpExpColorBackup { 
    Texture   = texExpColorBackup; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Backup texture for the last frame's depth.
texture texDepthBackup < pooled = true; > { 
    Width   = BUFFER_WIDTH; 
    Height  = BUFFER_HEIGHT; 
    Format  = R16f; 
};

sampler smpDepthBackup { 
    Texture   = texDepthBackup; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Point; 
    MinFilter = Point; 
    MagFilter = Point; 
};

/*=============================================================================
    Functions
=============================================================================*/

/**
 * @brief Samples a texture at a specified UV coordinate and mip level.
 *
 * @param s     Sampler reference of the texture.
 * @param uv    UV coordinate in texture space.
 * @param mip   Mip level to sample.
 * @return      The texture sample as a float4.
 */
float4 tex2Dlod(sampler s, float2 uv, float mip)
{
    return tex2Dlod(s, float4(uv, 0, mip));
}

/**
 * @brief Converts an RGB color to the YCbCr color space.
 *
 * @param rgb   Input RGB color.
 * @return      Corresponding color in YCbCr space (float3).
 */
float3 cvtRgb2YCbCr(float3 rgb)
{
    float y  = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    float cb = (rgb.b - y) * 0.565;
    float cr = (rgb.r - y) * 0.713;

    return float3(y, cb, cr);
}

/**
 * @brief Converts a YCbCr color to RGB color space.
 *
 * @param YCbCr Input color in YCbCr format.
 * @return      Converted RGB color (float3).
 */
float3 cvtYCbCr2Rgb(float3 YCbCr)
{
    return float3(
        YCbCr.x + 1.403 * YCbCr.z,
        YCbCr.x - 0.344 * YCbCr.y - 0.714 * YCbCr.z,
        YCbCr.x + 1.770 * YCbCr.y
    );
}

/**
 * @brief Wrapper function converting RGB to an intermediate color space.
 *
 * Acts as a pass-through to cvtRgb2YCbCr.
 *
 * @param rgb   Input RGB color.
 * @return      Converted color in the intermediate space ("whatever" space).
 */
float3 cvtRgb2whatever(float3 rgb)
{
    return cvtRgb2YCbCr(rgb);
}

// float3 cvtRgb2whatever(float3 rgb)
// {
//     switch (UI_COLOR_CONVERSION_MODE)
//     {
//         case 1: // YCbCr
//             return cvtRgb2YCbCr(rgb);
//         default: // RGB
//             return rgb;
//     }
// }



/**
 * @brief Wrapper function converting the intermediate color space to RGB.
 *
 * Acts as a pass-through to cvtYCbCr2Rgb.
 *
 * @param whatever Input color in the intermediate ("whatever") space.
 * @return         Converted RGB color.
 */
float3 cvtWhatever2Rgb(float3 whatever)
{
    return cvtYCbCr2Rgb(whatever);
}

// float3 cvtWhatever2Rgb(float3 whatever)
// {
//     switch (UI_COLOR_CONVERSION_MODE)
//     {
//         case 1: // YCbCr
//             return cvtYCbCr2Rgb(whatever);
//         default: // RGB
//             return whatever;
//     }
// }


/**
 * @brief Performs bicubic interpolation using 5 sample points.
 *
 * Inspired by techniques from Marty, this function computes the filtered
 * value by calculating sample weights and positions.
 *
 * @param source    Sampler reference of the texture.
 * @param texcoord  Texture coordinate to be sampled.
 * @return          Interpolated color as float4.
 */
float4 bicubic_5(sampler source, float2 texcoord)
{
    // Compute the texture size.
    float2 texsize = tex2Dsize(source);

    // Convert texture coordinate to texel space.
    float2 UV = texcoord * texsize;

    // Determine the center of the texel grid.
    float2 tc = floor(UV - 0.5) + 0.5;

    // Compute the fractional part for weighting.
    float2 f = UV - tc;

    // Calculate powers of f needed for weight computation.
    float2 f2 = f * f;
    float2 f3 = f2 * f;

    // Compute weights for the neighboring texels.
    float2 w0 = f2 - 0.5 * (f3 + f);
    float2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
    float2 w3 = 0.5 * (f3 - f2);
    float2 w12 = 1.0 - w0 - w3;

    // Store sample weights and corresponding sample position offsets.
    float4 ws[3];
    ws[0].xy = w0;
    ws[1].xy = w12;
    ws[2].xy = w3;

    // Calculate sample positions in texel space.
    ws[0].zw = tc - 1.0;
    ws[1].zw = tc + 1.0 - w1 / w12;
    ws[2].zw = tc + 2.0;

    // Normalize the sample offsets to texture coordinate space.
    ws[0].zw /= texsize;
    ws[1].zw /= texsize;
    ws[2].zw /= texsize;

    // Combine neighboring samples weighted by the computed factors.
    float4 ret;
    ret  = tex2Dlod(source, float2(ws[1].z, ws[0].w), 0) * ws[1].x * ws[0].y;
    ret += tex2Dlod(source, float2(ws[0].z, ws[1].w), 0) * ws[0].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[1].z, ws[1].w), 0) * ws[1].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[2].z, ws[1].w), 0) * ws[2].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[1].z, ws[2].w), 0) * ws[1].x * ws[2].y;
    
    // Normalize the result.
    float normfact = 1.0 / (1.0 - (f.x - f2.x) * (f.y - f2.y) * 0.25);
    return max(0, ret * normfact);
}

/**
 * @brief Samples historical frame data using bicubic interpolation.
 *
 * Wraps the bicubic interpolation method to retrieve a filtered history value.
 *
 * @param historySampler Sampler for the history texture.
 * @param texcoord       Texture coordinate.
 * @return               Filtered historical sample as a float4.
 */
float4 sampleHistory(sampler2D historySampler, float2 texcoord)
{
    return bicubic_5(historySampler, texcoord);
}

/**
 * @brief Retrieves and linearizes the depth value from the depth texture.
 *
 * Converts the non-linear depth sample into a linear depth value and handles
 * reversed depth input when enabled.
 *
 * @param texcoord Texture coordinate.
 * @return         Linearized depth value.
 */
float getDepth(float2 texcoord)
{
    // Sample raw depth.
    float depth = tex2Dlod(smpDepthIn, texcoord, 0).x;

    #if RESHADE_DEPTH_INPUT_IS_REVERSED
        // Adjust for reversed depth if required.
        depth = 1.0 - depth;
    #endif

    // Define a near plane constant.
    const float N = 1.0;

    float factor = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE * 0.1;

    // Linearize depth based on the far plane parameter.
    depth /= factor - depth * (factor - N);

    return depth;
}


/*=============================================================================
    Motion Vector Imports
=============================================================================*/

namespace Deferred 
{
    // Texture storing motion vectors (RGBA16F).
    // XY: Delta UV; Z: Confidence; W: Depth.
    texture MotionVectorsTex { 
        Width  = BUFFER_WIDTH; 
        Height = BUFFER_HEIGHT; 
        Format = RG16F;
    };
    sampler sMotionVectorsTex { 
        Texture = MotionVectorsTex; 
    };

    /**
     * @brief Retrieves the motion vector at a given texture coordinate.
     *
     * @param uv Texture coordinate.
     * @return   Motion vector as a float2.
     */
    float2 get_motion(float2 uv)
    {
        return tex2Dlod(sMotionVectorsTex, uv, 0).xy;
    }
}


/*=============================================================================
    Shader Pass Functions
=============================================================================*/

/**
 * @brief Saves the current frame's color and depth into a backup texture.
 *
 * Samples the scene's color and computes the linearized depth for use in
 * later temporal filtering passes.
 *
 * @param position Unused screen-space position.
 * @param texcoord Texture coordinate.
 * @return         Color from the current frame with depth stored in the alpha channel.
 */
float4 PassSaveCur(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{
    // Retrieve and linearize depth.
    float depthOnly = getDepth(texcoord);

    // Sample current frame color and pack depth into alpha channel.
    return float4(tex2Dlod(smpInCur, texcoord, 0).rgb, depthOnly);
}

/**
 * @brief Applies the temporal filter for anti-aliasing.
 *
 * Blends the current frame with historical data based on motion vectors,
 * local contrast, and depth continuity. This minimizes aliasing artifacts
 * while also calculating the amount of adaptive sharpening.
 *
 * @param position Unused screen-space position.

 * @param texcoord Texture coordinate.
 * @return         Processed color after temporal filtering + sharpening factor.
 */
float4 PassTemporalFilter(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    // Sample current frame.
    float4 sampleCur = tex2Dlod(smpInCurBackup, texcoord, 0);
    float4 cvtColorCur = float4(cvtRgb2whatever(sampleCur.rgb), sampleCur.a);

    static const int samples = 9;

    // Offsets for a 3x3 neighborhood (center is at index 4).
    static const float2 nOffsets[samples] = { 
		float2(-0.7,-0.7), float2(0, 1),  float2(0.7, 0.7), 
        float2(-1, 0),     float2(0, 0),  float2(1, 0), 
        float2(-0.7, 0.7), float2(0, -1), float2(0.7, 0.7) 
	};


    // The center of the neighborhood (index 4) is assumed to have the closest depth.
    int closestDepthIndex = 4;

    // Initialize min/max bounds
    float4 minimumCvt = 2;
    float4 maximumCvt = -1;

    // Sample the neighborhood and update min/max colors in clamping color space.
    for (int i = 0; i < samples; i++)
    {
        float4 rgba = tex2Dlod(smpInCurBackup, texcoord + (nOffsets[i] * ReShade::PixelSize), 0);
        float4 cvt = float4(cvtRgb2whatever(rgba.rgb), rgba.a);

        if (rgba.a < minimumCvt.a)
            closestDepthIndex = i;

        minimumCvt = min(minimumCvt, cvt);
        maximumCvt = max(maximumCvt, cvt);
    }

    // Retrieve dilated motion vector.
    float2 motion = Deferred::get_motion(texcoord + (nOffsets[closestDepthIndex] * ReShade::PixelSize));

    // Compute the corresponding sample position from the previous frame.
    float2 lastSamplePos = texcoord + motion;

    // Sample exponential color and last depth.
    float4 sampleExp = saturate(sampleHistory(smpExpColorBackup, lastSamplePos));
    float lastDepth = tex2Dlod(smpDepthBackup, lastSamplePos, 0).r;


    // Compute temporal weight factors 
    float localContrast= saturate(pow(length(maximumCvt.rgb - minimumCvt.rgb), 0.75));
    float speed        = length(motion.xy);
    float speedFactor  = 1.0 - pow(saturate(speed * 50), 0.75);

    // Calculate the depth difference and construct a disocclusion mask.
    float depthDelta = saturate(minimumCvt.a - lastDepth);
    depthDelta = saturate(pow(depthDelta, 4) - 0.0000001);
    float depthMask = 1.0 - (depthDelta * 10000000);

    // Compute the blending weight.
    float weight = lerp(0.5, 0.99, pow(UI_TEMPORAL_FILTER_STRENGTH, 0.5));
    weight = clamp(weight * speedFactor * saturate(localContrast + 0.75) * depthMask, 0.0, 0.99);

    // This factor is used to weight bright pixels more during blending, preserving highlights.
    const static float correctionFactor = 2;

    // The actual blending of the old exponential color with the new one.
    float4 blendedColor = saturate(pow(lerp(pow(sampleCur, correctionFactor), pow(sampleExp, correctionFactor), weight), (1.0 / correctionFactor)));  

    // This converts the blended color to the intermediate color space.
    blendedColor = float4(cvtRgb2whatever(blendedColor.rgb), blendedColor.a);

    // Clamp the blended color to the local neighborhood bounds.
    blendedColor = float4(clamp(blendedColor.rgb, minimumCvt.rgb, maximumCvt.rgb), blendedColor.a);

    // Convert the blended color back to RGB.
    blendedColor = float4(cvtWhatever2Rgb(blendedColor.rgb), blendedColor.a);

    //Calulate Sharpeninbg factor. 
    float sharp = saturate(UI_POST_SHARPEN * UI_TEMPORAL_FILTER_STRENGTH * pow(speed * 2048, 0.5) * localContrast * depthMask);



    float3 return_value = blendedColor.rgb;
    // switch (UI_DEBUG_MODE)
    // {
    //     case 1:
    //         return_value = weight;
    //         break;
    //     case 2:
    //         return_value = sharp;
    //         break;
    //     case 3:
    //         return_value = depthMask;
    //         break;
    //     default:
    //         break;
    // }

    // Return the final blended color and sharpening factor.
    return float4(return_value, sharp);
}

/**
 * @brief Saves the post-processed exponential color and depth for history.
 *
 * This pass stores the final exponential color buffer and the corresponding
 * linearized depth value for usage in subsequent frames.
 *
 * @param position    Unused screen-space position.
 * @param texcoord    Texture coordinate.
 * @param lastExpOut  Output exponential color buffer.
 * @param depthOnly   Output linearized depth.
 */
void PassSavePost(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 lastExpOut : SV_Target0, out float depthOnly : SV_Target1)
{
    // Store the current exponential color.
    lastExpOut = tex2Dlod(smpExpColor, texcoord, 0);

    // Store the corresponding linearized depth.
    depthOnly = getDepth(texcoord);
}

/**
 * @brief Final output pass that applies adaptive sharpening.
 *
 * Applies adaptive sharpening to the final image.
 *
 * @param position Unused screen-space position.
 * @param texcoord Texture coordinate.
 * @return         The final processed color with sharpening applied.
 */
float4 PassSharp(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
    // Sample the center and neighboring pixels.
    float4 center     = tex2Dlod(smpExpColor, texcoord, 0);
    float4 top        = tex2Dlod(smpExpColor, texcoord + (float2(0, -1) * ReShade::PixelSize), 0);
    float4 bottom     = tex2Dlod(smpExpColor, texcoord + (float2(0,  1) * ReShade::PixelSize), 0);
    float4 left       = tex2Dlod(smpExpColor, texcoord + (float2(-1, 0) * ReShade::PixelSize), 0);
    float4 right      = tex2Dlod(smpExpColor, texcoord + (float2(1,  0) * ReShade::PixelSize), 0);

    // Find the maximum and minimum among the sampled neighbors.
    float4 maxBox = max(top, max(bottom, max(left, max(right, center))));
    float4 minBox = min(top, min(bottom, min(left, min(right, center))));

    // Fixed contrast value (tuned for high temporal blur scenarios).
    float contrast = 0.8;
    float sharpAmount = saturate(maxBox.a * 10); 

    // Calculate cross weights similarly to AMD CAS.
    float4 crossWeight = -rcp(rsqrt(saturate(min(minBox, 1.0 - maxBox) * rcp(maxBox))) * (-3.0 * contrast + 8.0));

    // Compute reciprocal weight based on the sum of the cross weights.
    float4 rcpWeight = rcp(4.0 * crossWeight + 1.0);

    // Sum the direct neighbors (top, bottom, left, right).
    float4 crossSumm = top + bottom + left + right;
    
    // Combine center pixel with weighted neighbors.
    return lerp(center, saturate((crossSumm * crossWeight + center) * rcpWeight), sharpAmount);

}


/*=============================================================================
    Shader Technique: TFAA
=============================================================================*/

/**
 * @brief Temporal Filter Anti-Aliasing Technique.
 *
 * The technique is composed of the following passes:
 *   - PassSavePre: Saves the current frame's color and depth.
 *   - PassTemporalFilter: Applies temporal filtering using history and motion vectors.
 *   - PassSavePost: Stores the exponential color buffer and depth for history.
 *   - PassShow: Outputs the final image with adaptive sharpening.
 */
technique TFAA
<
    ui_label = "TFAA";
    ui_tooltip = "- Temporal Filter Anti-Aliasing -\nTemporal component of TAA to be used with (after) spatial anti-aliasing techniques.\nRequires motion vectors to be available (LAUNCHPAD.fx).";
>
{
    pass PassSavePre
    {
        VertexShader   = PostProcessVS;
        PixelShader    = PassSaveCur;
        RenderTarget   = texInCurBackup;
    }

    pass PassTemporalFilter
    {
        VertexShader   = PostProcessVS;
        PixelShader    = PassTemporalFilter;
        RenderTarget   = texExpColor;
    }

    pass PassSavePost
    {
        VertexShader   = PostProcessVS;
        PixelShader    = PassSavePost;
        RenderTarget0  = texExpColorBackup;
        RenderTarget1  = texDepthBackup;
    }

    pass PassShow
    {
        VertexShader   = PostProcessVS;
        PixelShader    = PassSharp;
    }
}