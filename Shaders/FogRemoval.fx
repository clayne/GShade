////////////////////////////////////////////////////////
// Fog Removal
// Author: Lord of Lunacy
// License: CC0 1.0 Universal
// https://creativecommons.org/publicdomain/zero/1.0/
// Repository: https://github.com/LordOfLunacy/Insane-Shaders
////////////////////////////////////////////////////////

/*
This shader attempts to remove fog so that affects that experience light bleeding from it can be applied,
and then reintroduce the fog over the image.

This code was inspired by features mentioned in the following paper:

B. Cai, X. X, K. Jia, C. Qing, and D. Tao, “DehazeNet: An End-to-End System for Single Image Haze Removal,”
IEEE Transactions on Image Processing, vol. 25, no. 11, pp. 5187–5198, 2016.
*/



#undef SAMPLEDISTANCE
#define SAMPLEDISTANCE 15

#define SAMPLEDISTANCE_SQUARED (SAMPLEDISTANCE*SAMPLEDISTANCE)
#define SAMPLEHEIGHT (BUFFER_HEIGHT / SAMPLEDISTANCE)
#define SAMPLEWIDTH (BUFFER_WIDTH / SAMPLEDISTANCE)
#define SAMPLECOUNT (SAMPLEHEIGHT * SAMPLEWIDTH)
#define SAMPLECOUNT_RCP (1/SAMPLECOUNT)
#define HISTOGRAMPIXELSIZE (1/255)



#include "ReShade.fxh"



uniform float STRENGTH<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Strength";
	ui_tooltip = "Setting strength to high is known to cause bright regions to turn black before reintroduction.";
	ui_bind = "FOGREMOVALSTRENGTH";
> = 0.950;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALSTRENGTH
#define FOGREMOVALSTRENGTH 0.950
#endif

uniform float DEPTHCURVE<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Depth Curve";
	ui_bind = "FOGREMOVALDEPTHCURVE";
> = 0.0;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALDEPTHCURVE
#define FOGREMOVALDEPTHCURVE 0.0
#endif

uniform float REMOVALCAP<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Fog Removal Cap";
	ui_tooltip = "Prevents fog removal from trying to extract more details than can actually be removed, \n"
		"also helps preserve textures or lighting that may be detected as fog.";
	ui_bind = "FOGREMOVALREMOVALCAP";
> = 0.35;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALREMOVALCAP
#define FOGREMOVALREMOVALCAP 0.35
#endif

uniform float MEDIANBOUNDSX<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Average Light Level (Day)";
	ui_tooltip = "This number should correspond to the average amount of light during the day.";
	ui_bind = "FOGREMOVALMEDIANBOUNDSX";
> = 0.2;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALMEDIANBOUNDSX
#define FOGREMOVALMEDIANBOUNDSX 0.2
#endif

uniform float MEDIANBOUNDSY<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Average Light Level (Night)";
	ui_tooltip = "This number should correspond to the average amount of light at night.";
	ui_bind = "FOGREMOVALMEDIANBOUNDSY";
> = 0.8;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALMEDIANBOUNDSY
#define FOGREMOVALMEDIANBOUNDSY 0.8
#endif

uniform float SENSITIVITYBOUNDSX<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Fog Sensitivity (Day)";
	ui_tooltip = "This number adjusts how sensitive the shader is to fog, a lower number means that \n"
			"it will detect more fog in the scene, but will also be more vulnerable to false positives.\n"
			"A higher number means that it will detect less fog in the scene but will also be more \n"
			"likely to fail at detecting fog.";
	ui_bind = "FOGREMOVALSENSITIVITYBOUNDSX";
> = 0.2;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALSENSITIVITYBOUNDSX
#define FOGREMOVALSENSITIVITYBOUNDSX 0.2
#endif

uniform float SENSITIVITYBOUNDSY<
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Fog Sensitivity (Night)";
	ui_tooltip = "This number adjusts how sensitive the shader is to fog, a lower number means that \n"
			"it will detect more fog in the scene, but will also be more vulnerable to false positives.\n"
			"A higher number means that it will detect less fog in the scene but will also be more \n"
			"likely to fail at detecting fog.";
	ui_bind = "FOGREMOVALSENSITIVITYBOUNDSY";
> = 0.75;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALSENSITIVITYBOUNDSY
#define FOGREMOVALSENSITIVITYBOUNDSY 0.75
#endif

uniform bool USEDEPTH<
	ui_label = "Ignore the sky";
	ui_tooltip = "Useful for shaders such as RTGI that rely on skycolor";
	ui_bind = "FOGREMOVALUSEDEPTH";
> = 0;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALUSEDEPTH
#define FOGREMOVALUSEDEPTH 0
#endif

uniform bool PRESERVEDETAIL<
	ui_label = "Preserve Detail";
	ui_category = "Fog Removal";
	ui_tooltip = "Preserves finer details at the cost of some haloing and some performance.";
	ui_bind = "FOGREMOVALPRESERVEDETAIL";
> = 1;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALPRESERVEDETAIL
#define FOGREMOVALPRESERVEDETAIL 1
#endif
	
uniform bool CORRECTCOLOR<
	ui_category = "Color Correction";
	ui_label = "Apply color correction";
	ui_tooltip = "Helps with detecting fog that is not neutral in color. \n\n"
			"Note: This setting is not always needed or may sometimes \n"
			"      hinder fog removal.";
	ui_bind = "FOGREMOVALCORRECTCOLOR";
> = 1;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALCORRECTCOLOR
#define FOGREMOVALCORRECTCOLOR 1
#endif
	
uniform float MAXPERCENTILE<
	ui_type = "slider";
	ui_label = "Color Correction Percentile";
	ui_category = "Color Correction";
	ui_min = 0.0; ui_max = 0.999;
	ui_tooltip = "This percentile is the one used when finding the max RGB values for color correction, \n"
			"having this set high may cause issues with things like UI elements, and image stability.";
	ui_bind = "FOGREMOVALMAXPERCENTILE";
> = 0.95;

// Set default value(see above) by source code if the preset has not modified yet this variable/definition
#ifndef FOGREMOVALMAXPERCENTILE
#define FOGREMOVALMAXPERCENTILE 0.95
#endif

uniform int DEBUG<
	ui_type = "combo";
	ui_category = "Debug";
	ui_label = "Debug";
	ui_items = "None \0Color Correction \0Transmission Map \0Fog Removed \0";
	ui_bind = "FOGREMOVALDEBUG";
> = 0;

#ifndef FOGREMOVALDEBUG
#define FOGREMOVALDEBUG 0
#endif



texture ColorCorrected {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F;};
sampler sColorCorrected {Texture = ColorCorrected;};
texture fTransmission {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8;};
sampler sTransmission {Texture = fTransmission;};
texture FogRemovalHistogram {Width = 256; Height = 12; Format = R32F;};
sampler sFogRemovalHistogram {Texture = FogRemovalHistogram;};
texture HistogramInfo {Width = 1; Height = 1; Format = RGBA8;};
sampler sHistogramInfo {Texture = HistogramInfo;};
texture FogRemoved {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F;};
sampler sFogRemoved {Texture = FogRemoved;};
texture TruncatedPrecision {Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F;};
sampler sTruncatedPrecision {Texture = TruncatedPrecision;};



void HistogramVS(uint id : SV_VERTEXID, out float4 pos : SV_POSITION)
{
	const uint iteration = (id % 4);
	const int2 texturePos = int2((uint(id / 4) % SAMPLEWIDTH) * SAMPLEDISTANCE, (uint(id / 4) / SAMPLEWIDTH) * SAMPLEDISTANCE);
	float color;
	float y;
	
	switch (iteration)
	{
		case 0:
			color = dot(tex2Dfetch(ReShade::BackBuffer, texturePos, 0).rgb, float3(0.33333333, 0.33333333, 0.33333333));
			y = 0.75;
			break;
		case 1:
			color = tex2Dfetch(ReShade::BackBuffer, texturePos, 0).r;
			y = 0.25;
			break;
		case 2:
			color = tex2Dfetch(ReShade::BackBuffer, texturePos, 0).g;
			y = -0.25;
			break;
		case 3:
			color = tex2Dfetch(ReShade::BackBuffer, texturePos, 0).b;
			y = -0.75;
			break;
	}

	color = (color * 255 + 0.5) / 256;
	pos = float4(color * 2 - 1, y, 0, 1);
}



void HistogramPS(float4 pos : SV_POSITION, out float col : SV_TARGET )
{
	col = 1.0;
}

void HistogramInfoPS(float4 pos : SV_Position, out float4 output : SV_Target0)
{
	const int fifty = abs(0.5 * SAMPLECOUNT);
	const int usedMax = abs(FOGREMOVALMAXPERCENTILE * SAMPLECOUNT);
	int4 sum = SAMPLECOUNT;
	output = 255.0;
	int i = 255;
	while((sum.r <= SAMPLECOUNT || sum.g <= SAMPLECOUNT || sum.b <= SAMPLECOUNT || sum.a <= SAMPLECOUNT) && i >= 0)
	{
#if	FOGREMOVALCORRECTCOLOR == 1
		sum.r -= tex2Dfetch(sFogRemovalHistogram, int2(i, 4), 0).r;
		sum.g -= tex2Dfetch(sFogRemovalHistogram, int2(i, 7), 0).r;
		sum.b -= tex2Dfetch(sFogRemovalHistogram, int2(i, 10), 0).r;
		if (sum.r < usedMax)
		{
			sum.r = 2 * SAMPLECOUNT;
			output.r = i;
		}
		if (sum.g < usedMax)
		{
			sum.g = 2 * SAMPLECOUNT;
			output.g = i;
		}
		if (sum.b < usedMax)
		{
			sum.b = 2 * SAMPLECOUNT;
			output.b = i;
		}
#else
		sum.rgb = -SAMPLECOUNT;
#endif
		sum.a -= tex2Dfetch(sFogRemovalHistogram, int2(i, 1), 0).r;
		if (sum.a < fifty)
		{
			sum.a =  2 * SAMPLECOUNT;
			output.a = i;
		}
		i--;
	}
	output = output / 255.0;
	output.rgb = dot(0.33333333, output.rgb) / output.rgb;
}

void ColorCorrectedPS(float4 pos: SV_Position, float2 texcoord : TexCoord, out float4 colorCorrected : SV_Target0)
{
#if FOGREMOVALCORRECTCOLOR == 1
	colorCorrected = float4(tex2D(ReShade::BackBuffer, texcoord).rgb * tex2Dfetch(sHistogramInfo, float2(0, 0), 0).rgb, 1);
#else
	colorCorrected = float4(tex2D(ReShade::BackBuffer, texcoord).rgb, 1);
#endif
}

void TransmissionPS(float4 pos: SV_Position, float2 texcoord : TexCoord, out float transmission : SV_Target0)
{
	const float depth = ReShade::GetLinearizedDepth(texcoord);

#if FOGREMOVALUSEDEPTH == 1
	if (depth >= 1)
	{
		transmission = 0;
		return;
	}
#endif

	float3 color = tex2D(sColorCorrected, texcoord).rgb;
	const float value = max(max(color.r, color.g), color.b);
	const float minimum = min(min(color.r, color.g), color.b);
	float darkChannel = minimum;

#if FOGREMOVALPRESERVEDETAIL == 1
	float2 pixSize = tex2Dsize(sColorCorrected, 0);
	pixSize.x = 1 / pixSize.x;
	pixSize.y = 1 / pixSize.y;
	float depthContrast = 0;

	[unroll]for(int i = -2; i <= 2; i++)
	{
		float depthSum = 0;
		[unroll]for(int j = -2; j <= 2; j++)
		{
			color = tex2D(sColorCorrected, texcoord, int2(i, j)).rgb;
			darkChannel = min(min(color.r, color.g), min(color.b, darkChannel));
			float2 matrixCoord;
			matrixCoord.x = texcoord.x + pixSize.x * i;
			matrixCoord.y = texcoord.y + pixSize.y * j;
			float depthSubtract = depth - ReShade::GetLinearizedDepth(matrixCoord);
			depthSum += depthSubtract * depthSubtract;
		}
		depthContrast = max(depthContrast, depthSum);
	}
	depthContrast = sqrt(0.2 * depthContrast);
	darkChannel = lerp(darkChannel, minimum, saturate(2 * depthContrast));
#endif

	const float v = (clamp(tex2Dfetch(sHistogramInfo, int2(0, 0), 0).a, FOGREMOVALMEDIANBOUNDSX, FOGREMOVALMEDIANBOUNDSY) - FOGREMOVALMEDIANBOUNDSX) * ((FOGREMOVALSENSITIVITYBOUNDSX - FOGREMOVALSENSITIVITYBOUNDSY) / (FOGREMOVALMEDIANBOUNDSX - FOGREMOVALMEDIANBOUNDSY)) + FOGREMOVALSENSITIVITYBOUNDSX;
	transmission = clamp(saturate((darkChannel / (1 - (value - ((value - minimum) / (value))))) - v * (darkChannel + darkChannel)) * (1 - v), 0, FOGREMOVALREMOVALCAP) * saturate((pow(depth, 100*FOGREMOVALDEPTHCURVE)) * FOGREMOVALSTRENGTH);
}

void FogRemovalPS(float4 pos: SV_Position, float2 texcoord : TexCoord, out float4 output : SV_Target0)
{
	const float transmission = tex2D(sTransmission, texcoord).r;
	output.rgb = (tex2D(sColorCorrected, texcoord).rgb - transmission) / max(((1 - transmission)), 0.01);
#if FOGREMOVALCORRECTCOLOR == 1
	output.rgb /= tex2Dfetch(sHistogramInfo, float2(0, 0), 0).rgb;
#endif

	output = float4(output.rgb, 1);

#if FOGREMOVALDEBUG == 1
	output = tex2D(sColorCorrected, texcoord).rgb;
#elif FOGREMOVALDEBUG == 2
	output = transmission;
#endif
}

void WriteFogRemovedPS(float4 pos: SV_Position, float2 texcoord : TexCoord, out float3 output : SV_Target0)
{
	output = tex2D(sFogRemoved, texcoord).rgb;
}

void TruncatedPrecisionPS(float4 pos: SV_Position, float2 texcoord : TexCoord, out float4 output : SV_Target0)
{
	output = float4((tex2D(sFogRemoved, texcoord).rgb - tex2D(ReShade::BackBuffer, texcoord).rgb), 1);
}

void FogReintroductionPS(float4 pos : SV_Position, float2 texcoord : TexCoord, out float3 output : SV_Target0)
{
#if FOGREMOVALUSEDEPTH == 1
	if (ReShade::GetLinearizedDepth(texcoord) >= 1) discard;
#endif

	const float transmission = tex2D(sTransmission, texcoord).r;
	float3 original = tex2D(ReShade::BackBuffer, texcoord).rgb + tex2D(sTruncatedPrecision, texcoord).rgb;

#if FOGREMOVALCORRECTCOLOR == 1
	original *= tex2Dfetch(sHistogramInfo, float2(0, 0), 0).rgb;
#endif

	output = original * max(((1 - transmission)), 0.01) + transmission;

#if FOGREMOVALCORRECTCOLOR == 1
	output /= tex2Dfetch(sHistogramInfo, float2(0, 0), 0).rgb;
#endif

#if FOGREMOVALDEBUG > 0
	output = tex2D(sFogRemoved, texcoord).rgb;
#endif
}



technique FogRemoval
{
	pass Histogram
	{
		PixelShader = HistogramPS;
		VertexShader = HistogramVS;
		PrimitiveTopology = POINTLIST;
		VertexCount = SAMPLECOUNT * 4;
		RenderTarget0 = FogRemovalHistogram;
		ClearRenderTargets = true; 
		BlendEnable = true; 
		SrcBlend = ONE; 
		DestBlend = ONE;
		BlendOp = ADD;
	}

	pass HistogramInfo
	{
		VertexShader = PostProcessVS;
		PixelShader = HistogramInfoPS;
		RenderTarget0 = HistogramInfo;
		ClearRenderTargets = true;
	}

	pass ColorCorrected
	{
		VertexShader = PostProcessVS;
		PixelShader = ColorCorrectedPS;
		RenderTarget0 = ColorCorrected;
	}

	pass Transmission
	{
		VertexShader = PostProcessVS;
		PixelShader = TransmissionPS;
		RenderTarget0 = fTransmission;
	}

	pass FogRemoval
	{
		VertexShader = PostProcessVS;
		PixelShader = FogRemovalPS;
		RenderTarget0 = FogRemoved;
	}

	pass FogRemoved
	{
		VertexShader = PostProcessVS;
		PixelShader = WriteFogRemovedPS;
	}

	pass TruncatedPrecision
	{
		VertexShader = PostProcessVS;
		PixelShader = TruncatedPrecisionPS;
		RenderTarget0 = TruncatedPrecision;
	}
}

technique FogReintroduction <ui_tooltip = "Place this after the shaders you want to be rendered without fog";>
{
	pass Reintroduction
	{
		VertexShader = PostProcessVS;
		PixelShader = FogReintroductionPS;
	}
}
