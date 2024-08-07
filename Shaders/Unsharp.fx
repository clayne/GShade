////////////////////////////////////////////////////////
// Unsharp
// Author: luluco250
// License: MIT
// Repository: https://github.com/luluco250/FXShaders
////////////////////////////////////////////////////////
/*
MIT License

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

#include "FXShadersBlending.fxh"
#include "FXShadersCommon.fxh"
#include "FXShadersConvolution.fxh"

#if GSHADE_DITHER
    #include "TriDither.fxh"
#endif

#ifndef UNSHARP_BLUR_SAMPLES
#define UNSHARP_BLUR_SAMPLES 21
#endif

namespace FXShaders
{

static const int BlurSamples = UNSHARP_BLUR_SAMPLES;

uniform float Amount
<
	ui_category = "Appearance";
	ui_label = "Amount";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
> = 1.0;

uniform float BlurScale
<
	ui_category = "Appearance";
	ui_label = "Blur Scale";
	ui_type = "slider";
	ui_min = 0.01;
	ui_max = 1.0;
> = 1.0;

texture ColorTex : COLOR;

sampler ColorSRGB
{
	Texture = ColorTex;
	// SRGBTexture = true;
};

sampler ColorLinear
{
	Texture = ColorTex;
};

texture OriginalTex
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;

	#if BUFFER_COLOR_DEPTH == 10
		Format = RGB10A2;
	#endif
};

sampler Original
{
	Texture = OriginalTex;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
};

float4 Blur(sampler tex, float2 uv, float2 dir)
{
	float4 color = GaussianBlur1D(
		tex,
		uv,
		dir * GetPixelSize() * 3.0,
		sqrt(BlurSamples) * BlurScale,
		BlurSamples
	);

	//color = color * (GetRandom(uv) * 0.5 + 1.0);
	return color + abs(GetRandom(uv) - 0.5) * FloatEpsilon * 25.0;
}

float4 CopyOriginalPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
	return tex2D(ColorSRGB, uv);
}

#define DEF_BLUR_SHADER(index, tex, dir) \
float4 Blur##index##PS( \
	float4 p : SV_POSITION, \
	float2 uv : TEXCOORD) : SV_TARGET \
{ \
	return Blur(tex, uv, dir); \
}

DEF_BLUR_SHADER(0, ColorSRGB, float2(1.0, 0.0));

DEF_BLUR_SHADER(1, ColorLinear, float2(0.0, 4.0));

DEF_BLUR_SHADER(2, ColorLinear, float2(4.0, 0.0));

DEF_BLUR_SHADER(3, ColorLinear, float2(0.0, 1.0));

float4 BlendPS(float4 p : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET
{
#if GSHADE_DITHER
	float4 color = tex2D(Original, uv);

	color.rgb = BlendOverlay(color.rgb, GetLumaGamma(1.0 - tex2D(ColorLinear, uv).rgb) * 0.75, Amount);

	return float4(color.rgb + TriDither(color.rgb, uv, BUFFER_COLOR_BIT_DEPTH), color.a);
#else
	const float4 color = tex2D(Original, uv);

	return float4(BlendOverlay(color.rgb, GetLumaGamma(1.0 - tex2D(ColorLinear, uv).rgb) * 0.75, Amount), color.a);
#endif
}

technique Unsharp
{
	pass CopyOriginal
	{
		VertexShader = ScreenVS;
		PixelShader = CopyOriginalPS;
		RenderTarget = OriginalTex;
	}
	pass Blur0
	{
		VertexShader = ScreenVS;
		PixelShader = Blur0PS;
	}
	pass Blur1
	{
		VertexShader = ScreenVS;
		PixelShader = Blur1PS;
	}
	pass Blur2
	{
		VertexShader = ScreenVS;
		PixelShader = Blur2PS;
	}
	pass Blur3
	{
		VertexShader = ScreenVS;
		PixelShader = Blur3PS;
	}
	pass Blend
	{
		VertexShader = ScreenVS;
		PixelShader = BlendPS;
		// SRGBWriteEnable = true;
	}
}

}
