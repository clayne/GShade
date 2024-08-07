/**
 * Levels version 1.2
 * by Christian Cann Schuldt Jensen ~ CeeJay.dk
 * License: MIT
 *
 * Allows you to set a new black and a white level.
 * This increases contrast, but clips any colors outside the new range to either black or white
 * and so some details in the shadows or highlights can be lost.
 *
 * The shader is very useful for expanding the 16-235 TV range to 0-255 PC range.
 * You might need it if you're playing a game meant to display on a TV with an emulator that does not do this.
 * But it's also a quick and easy way to uniformly increase the contrast of an image.
 *
 * -- Version 1.0 --
 * First release
 * -- Version 1.1 --
 * Optimized to only use 1 instruction (down from 2 - a 100% performance increase :) )
 * -- Version 1.2 --
 * Added the ability to highlight clipping regions of the image with #define HighlightClipping 1
 *
 *
 * The MIT License (MIT)
 * 
 * Copyright (c) 2014 CeeJayDK
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
 // Lightly optimized by Marot Satil for the GShade project.

uniform int BlackPoint <
	ui_type = "slider";
	ui_min = 0; ui_max = 255;
	ui_label = "Black Point";
	ui_tooltip = "The black point is the new black - literally. Everything darker than this will become completely black.";
> = 16;

uniform int WhitePoint <
	ui_type = "slider";
	ui_min = 0; ui_max = 255;
	ui_label = "White Point";
	ui_tooltip = "The new white point. Everything brighter than this becomes completely white";
> = 235;

uniform bool HighlightClipping <
	ui_label = "Highlight clipping pixels";
	ui_tooltip = "Colors between the two points will stretched, which increases contrast, but details above and below the points are lost (this is called clipping).\n"
		"This setting marks the pixels that clip.\n"
		"Red: Some detail is lost in the highlights\n"
		"Yellow: All detail is lost in the highlights\n"
		"Blue: Some detail is lost in the shadows\n"
		"Cyan: All detail is lost in the shadows.";
> = false;

#include "ReShade.fxh"

#if GSHADE_DITHER
    #include "TriDither.fxh"
#endif

float3 LevelsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	const float black_point_float = BlackPoint / 255.0;

	float white_point_float;
	// Avoid division by zero if the white and black point are the same
	if (WhitePoint == BlackPoint)
		white_point_float = (255.0 / 0.00025);
	else
		white_point_float = 255.0 / (WhitePoint - BlackPoint);

	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = color * white_point_float - (black_point_float *  white_point_float);

	if (HighlightClipping)
	{
		float3 clipped_colors;

		// any colors whiter than white?
		if (any(color > saturate(color)))
			clipped_colors = float3(1.0, 0.0, 0.0);
		else
			clipped_colors = color;

		// all colors whiter than white?
		if (all(color > saturate(color)))
			clipped_colors = float3(1.0, 1.0, 0.0);

		// any colors blacker than black?
		if (any(color < saturate(color)))
			clipped_colors = float3(0.0, 0.0, 1.0);

		// all colors blacker than black?
		if (all(color < saturate(color)))
			clipped_colors = float3(0.0, 1.0, 1.0);

		color = clipped_colors;
	}

#if GSHADE_DITHER
	return color + TriDither(color, texcoord, BUFFER_COLOR_BIT_DEPTH);
#else
	return color;
#endif
}

technique Levels
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = LevelsPass;
	}
}
