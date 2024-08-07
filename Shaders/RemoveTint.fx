/*******************************************************
	ReShade Shader: RemoveTint
	https://github.com/Daodan317081/reshade-shaders
	License: BSD 3-Clause

	BSD 3-Clause License

	Copyright (c) 2018-2019, Alexander Federwisch
	All rights reserved.

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:

	* Redistributions of source code must retain the above copyright notice, this
	list of conditions and the following disclaimer.

	* Redistributions in binary form must reproduce the above copyright notice,
	this list of conditions and the following disclaimer in the documentation
	and/or other materials provided with the distribution.

	* Neither the name of the copyright holder nor the names of its
	contributors may be used to endorse or promote products derived from
	this software without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
	IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
	FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
	DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
	SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
	OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*******************************************************/

#include "ReShade.fxh"

#if GSHADE_DITHER
    #include "TriDither.fxh"
#endif

uniform float fUISpeed <
	ui_type = "slider";
	ui_label = "Adaptions Speed";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.01;
> = 0.1;

uniform bool bUIUseExcludeColor <
	ui_spacing = 5;
	ui_tooltip = "Enable this to exclude a certain color from being used in the min/max-RGB calculation. Can reduce the impact of the game UI.";
	ui_type = "radio";
	ui_label = "Enable Exclude Color";
> = false;

uniform float3 fUIExcludeColor <
	ui_type = "color";
	ui_label = "Exclude Color";
> = float3(1.0, 1.0, 1.0);

uniform float fUIExcludeColorStrength <
	ui_type = "slider";
	ui_label = "Strength";
	ui_min = 1.0; ui_max = 4.0;
> = 3.0;

uniform int cUIDebug <
	ui_type = "combo";
	ui_label = "Debug";
	ui_items = "Off\0Show Diff To Avg. RGB\0";
> = 0;

uniform float fUIStrength <
	ui_spacing = 5;
	ui_type = "slider";
	ui_label = "Strength";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.01;
> = 1.0;

uniform float frametime < source = "frametime"; >;

namespace RemoveTint {

	#ifndef REMOVE_TINT_MIPLEVEL_EXP2
		#define REMOVE_TINT_MIPLEVEL_EXP2 16
	#endif

	texture2D texBackBuffer { Width = BUFFER_WIDTH/REMOVE_TINT_MIPLEVEL_EXP2; Height = BUFFER_HEIGHT/REMOVE_TINT_MIPLEVEL_EXP2; Format = RGBA16F; };
	sampler2D samplerBackBuffer { Texture = texBackBuffer; };

	texture2D texMinRGB { Width = 1; Height = 1; Format = RGBA16F; };
	sampler2D samplerMinRGB { Texture = texMinRGB; };
	texture2D texMaxRGB { Width = 1; Height = 1; Format = RGBA16F; };
	sampler2D samplerMaxRGB { Texture = texMaxRGB; };

	texture2D texMinRGBLastFrame { Width = 1; Height = 1; Format = RGBA16F; };
	sampler2D samplerMinRGBLastFrame { Texture = texMinRGBLastFrame; };
	texture2D texMaxRGBLastFrame { Width = 1; Height = 1; Format = RGBA16F; };
	sampler2D samplerMaxRGBLastFrame { Texture = texMaxRGBLastFrame; };

	float LerpValue(float luma, float2 values) {
		return ((smoothstep(0.0, 1.0, 4.0 * luma - ((1.0 - values.x) *2.0 - 1.0)) + (1.0 - smoothstep(0.0, 1.0, 4.0 * luma - (2.0 + (values.y)*2.0)))) * 0.5 - 0.5) * 2.0;
	}

	void BackBuffer_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 backbuffer : SV_Target0) {
		backbuffer = tex2Dfetch(ReShade::BackBuffer, int2(vpos.xy * REMOVE_TINT_MIPLEVEL_EXP2), 0);
	}

	void MinMaxRGB_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 resultMinRGB : SV_Target0, out float4 resultMaxRGB : SV_Target1) {
		float diff;
		float brightnessFilter;
		float luma;
		float lerpValue;
		float3 color;
		float4 currentMinRGB = 1.0.rrrr;
		float4 currentMaxRGB = 0.0.rrrr;

		const int2 size = BUFFER_SCREEN_SIZE / REMOVE_TINT_MIPLEVEL_EXP2;

		for(int y = 0; y < size.y; y++) {
			for(int x = 0; x < size.x; x++) {
				color = tex2Dfetch(RemoveTint::samplerBackBuffer, int2(x, y), 0).rgb;
				luma = dot(color, float3(0.2126, 0.7151, 0.0721));
				diff = saturate(pow(abs(dot(color, fUIExcludeColor)), fUIExcludeColorStrength));
				if (bUIUseExcludeColor)
					lerpValue = 1.0 - diff;
				else
					lerpValue = 1.0;

				currentMaxRGB.r = lerp(currentMaxRGB.r, color.r, min(step(currentMaxRGB.r, color.r), lerpValue));
				currentMaxRGB.g = lerp(currentMaxRGB.g, color.g, min(step(currentMaxRGB.g, color.g), lerpValue));
				currentMaxRGB.b = lerp(currentMaxRGB.b, color.b, min(step(currentMaxRGB.b, color.b), lerpValue));

				currentMinRGB.r = lerp(currentMinRGB.r, color.r, min(step(color.r, currentMinRGB.r), lerpValue));
				currentMinRGB.g = lerp(currentMinRGB.g, color.g, min(step(color.g, currentMinRGB.g), lerpValue));
				currentMinRGB.b = lerp(currentMinRGB.b, color.b, min(step(color.b, currentMinRGB.b), lerpValue));
			}
		}

		const float4 lastMinRGB = tex2Dfetch(RemoveTint::samplerMinRGBLastFrame, int2(0, 0), 0);
		const float4 lastMaxRGB = tex2Dfetch(RemoveTint::samplerMaxRGBLastFrame, int2(0, 0), 0);

		resultMinRGB = saturate(lerp(lastMinRGB, currentMinRGB, saturate(fUISpeed * frametime * 0.01)));
		resultMaxRGB = saturate(lerp(lastMaxRGB, currentMaxRGB, saturate(fUISpeed * frametime * 0.01)));
		resultMinRGB.a = 1.0;
		resultMaxRGB.a = 1.0;
	}

	void MinMaxRGBBackup_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 currentMinRGB : SV_Target0, out float4 currentMaxRGB : SV_Target1) {
		currentMinRGB = tex2Dfetch(RemoveTint::samplerMinRGB, int2(0, 0), 0);
		currentMaxRGB = tex2Dfetch(RemoveTint::samplerMaxRGB, int2(0, 0), 0);
	}

	float4 Apply_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
		const float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
		const float3 MinRGB = tex2Dfetch(RemoveTint::samplerMinRGB, int2(0, 0), 0).rgb;
		const float3 MaxRGB = tex2Dfetch(RemoveTint::samplerMaxRGB, int2(0, 0), 0).rgb;
		const float3 colorNormalize = (color - MinRGB) / (MaxRGB-MinRGB);
		float3 tintRemoved = colorNormalize;
		//Preserve brighness
		tintRemoved = normalize(tintRemoved) * length(color).rrr;
		//Don't apply fUIExcludeColor
		tintRemoved = lerp(tintRemoved, color, saturate(pow(abs(dot(color, fUIExcludeColor)), fUIExcludeColorStrength)));

#if GSHADE_DITHER
		const float3 outcolor = saturate(lerp(color, tintRemoved, fUIStrength)).rgb;
		return float4(outcolor + TriDither(outcolor, texcoord, BUFFER_COLOR_BIT_DEPTH), 1.0);
#else
		return float4(saturate(lerp(color, tintRemoved, fUIStrength)).rgb, 1.0);
#endif
	}
}

technique RemoveTint
{
	pass {
		VertexShader = PostProcessVS;
		PixelShader = RemoveTint::BackBuffer_PS;
		RenderTarget = RemoveTint::texBackBuffer;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = RemoveTint::MinMaxRGB_PS;
		RenderTarget0 = RemoveTint::texMinRGB;
		RenderTarget1 = RemoveTint::texMaxRGB;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = RemoveTint::MinMaxRGBBackup_PS;
		RenderTarget0 = RemoveTint::texMinRGBLastFrame;
		RenderTarget1 = RemoveTint::texMaxRGBLastFrame;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = RemoveTint::Apply_PS;
		/* RenderTarget = BackBuffer */
	}
}
