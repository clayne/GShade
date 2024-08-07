//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// ReShade effect file
// Eye Adaption by brussell
// v. 2.3_FFXIV - FFXIV Edit
//
// modified by healingbrew to disable adaptation 
// when occluded by UI
//
// Credits:
// luluco250 - luminance get/store code from Magic Bloom
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

/*
MIT License

Magic Bloom

Copyright (c) 2017 Lucas Melo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#include "ReShade.fxh"

#if GSHADE_DITHER
    #include "TriDither.fxh"
#endif

//effect parameters
uniform float fAdp_Delay <
    ui_label = "Adaption Delay";
    ui_tooltip = "How fast the image adapts to brightness changes.\n"
                 "0 = instantanous adaption\n"
                 "2 = very slow adaption";
    ui_category = "General settings";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.6;

uniform float fAdp_TriggerRadius <
    ui_label = "Adaption TriggerRadius";
    ui_tooltip = "Screen area, whose average brightness triggers adaption.\n"
                 "1 = only the center of the image is used\n"
                 "7 = the whole image is used";
    ui_category = "General settings";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 7.0;
    ui_step = 0.1;
> = 6.0;

uniform float fAdp_YAxisFocalPoint <
    ui_label = "Y Axis Focal Point";
    ui_tooltip = "Where along the Y Axis the Adaption TriggerRadius applies.\n"
                 "0 = Top of the screen\n"
                 "1 = Bottom of the screen";
    ui_category = "General settings";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float fAdp_Equilibrium <
    ui_label = "Adaption Equilibrium";
    ui_tooltip = "The value of image brightness for which there is no brightness adaption.\n"
                 "0 = late brightening, early darkening\n"
                 "1 = early brightening, late darkening";
    ui_category = "General settings";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float fAdp_Strength <
    ui_label = "Adaption Strength";
    ui_tooltip = "Base strength of brightness adaption.\n";
    ui_category = "General settings";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform bool bAdp_IgnoreOccludedByUI <
  ui_label = "Ignore Trigger Area if Occluded by UI (FFXIV)";
  ui_category = "General settings";
> = 0;

uniform float fAdp_IgnoreTreshold <
    ui_label = "Ignore Alpha Treshold";
    ui_tooltip = "How visible the UI must be to be ignored"
                 "0 = any UI, including window shadows prevents occlusion"
                 "1 = only 100% opaque windows prevent occlusion";
    ui_category = "General settings";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.2;

uniform float fAdp_BrightenHighlights <
    ui_label = "Brighten Highlights";
    ui_tooltip = "Brightening strength for highlights.";
    ui_category = "Brightening";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float fAdp_BrightenMidtones <
    ui_label = "Brighten Midtones";
    ui_tooltip = "Brightening strength for midtones.";
    ui_category = "Brightening";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.2;

uniform float fAdp_BrightenShadows <
    ui_label = "Brighten Shadows";
    ui_tooltip = "Brightening strength for shadows.\n"
                 "Set this to 0 to preserve pure black.";
    ui_category = "Brightening";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float fAdp_DarkenHighlights <
    ui_label = "Darken Highlights";
    ui_tooltip = "Darkening strength for highlights.\n"
                 "Set this to 0 to preserve pure white.";
    ui_category = "Darkening";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float fAdp_DarkenMidtones <
    ui_label = "Darken Midtones";
    ui_tooltip = "Darkening strength for midtones.";
    ui_category = "Darkening";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.2;

uniform float fAdp_DarkenShadows <
    ui_label = "Darken Shadows";
    ui_tooltip = "Darkening strength for shadows.";
    ui_category = "Darkening";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

//global vars
#define LumCoeff float3(0.212656, 0.715158, 0.072186)
uniform float Frametime < source = "frametime";>;

//textures and samplers
texture2D TexLuma { Width = 256; Height = 256; Format = R8; MipLevels = 7; };
texture2D TexAvgLuma { Format = R16F; };
texture2D TexAvgLumaLast { Format = R16F; };

sampler SamplerLuma { Texture = TexLuma; };
sampler SamplerAvgLuma { Texture = TexAvgLuma; };
sampler SamplerAvgLumaLast { Texture = TexAvgLumaLast; };

//pixel shaders
float PS_Luma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    const float4 color = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0));
    return dot(color.xyz, LumCoeff);
}

float PS_AvgLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    const float avgLumaCurrFrame = tex2Dlod(SamplerLuma, float4(fAdp_YAxisFocalPoint.xx, 0, fAdp_TriggerRadius)).x;
    const float avgLumaLastFrame = tex2Dlod(SamplerAvgLumaLast, float4(0.0.xx, 0, 0)).x;
    const float uiVisibility = tex2D(ReShade::BackBuffer, float2(0.5, 0.5)).a;
    if(bAdp_IgnoreOccludedByUI && uiVisibility > fAdp_IgnoreTreshold)
    {
        return avgLumaLastFrame;
    }
    const float delay = sign(fAdp_Delay) * saturate(0.815 + fAdp_Delay / 10.0 - Frametime / 1000.0);
    return lerp(avgLumaCurrFrame, avgLumaLastFrame, delay);
}

float AdaptionDelta(float luma, float strengthMidtones, float strengthShadows, float strengthHighlights)
{
    const float midtones = (4.0 * strengthMidtones - strengthHighlights - strengthShadows) * luma * (1.0 - luma);
    const float shadows = strengthShadows * (1.0 - luma);
    const float highlights = strengthHighlights * luma;
    return midtones + shadows + highlights;
}

float4 PS_Adaption(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = tex2Dlod(ReShade::BackBuffer, float4(texcoord, 0, 0));
    const float avgLuma = tex2Dlod(SamplerAvgLuma, float4(0.0.xx, 0, 0)).x;

    color.xyz = pow(abs(color.xyz), 1.0/2.2);
    float luma = dot(color.xyz, LumCoeff);
    const float3 chroma = color.xyz - luma;

    const float avgLumaAdjusted = lerp (avgLuma, 1.4 * avgLuma / (0.4 + avgLuma), fAdp_Equilibrium);
    float delta = 0;

    const float curve = fAdp_Strength * 10.0 * pow(abs(avgLumaAdjusted - 0.5), 4.0);
    if (avgLumaAdjusted < 0.5) {
        delta = AdaptionDelta(luma, fAdp_BrightenMidtones, fAdp_BrightenShadows, fAdp_BrightenHighlights);
    } else {
        delta = -AdaptionDelta(luma, fAdp_DarkenMidtones, fAdp_DarkenShadows, fAdp_DarkenHighlights);
    }
    delta *= curve;

    luma += delta;
    color.xyz = saturate(luma + chroma);
    color.xyz = pow(abs(color.xyz), 2.2);

#if GSHADE_DITHER
    return float4(color.xyz + TriDither(color.xyz, texcoord, BUFFER_COLOR_BIT_DEPTH), color.w);
#else
    return color;
#endif
}

float PS_StoreAvgLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2Dlod(SamplerAvgLuma, float4(0.0.xx, 0, 0)).x;
}

//techniques
technique EyeAdaption {

    pass Luma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Luma;
        RenderTarget = TexLuma;
    }

    pass AvgLuma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AvgLuma;
        RenderTarget = TexAvgLuma;
    }

    pass Adaption
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Adaption;
    }

    pass StoreAvgLuma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_StoreAvgLuma;
        RenderTarget = TexAvgLumaLast;
    }
}
