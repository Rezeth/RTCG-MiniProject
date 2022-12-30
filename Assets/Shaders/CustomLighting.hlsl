
//Guard keyword to prevent the shader graph from being compiled twice
#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

struct CustomLightingData {
    // Surface attributes
    float3 albedo;
};

float3 CalculateCustomLighting(CustomLightingData d) {
    return d.albedo;
}

void CalculateCustomLighting_float(float3 Albedo,
    out float3 Color) {

    CustomLightingData d;
    d.albedo = Albedo;

    Color = CalculateCustomLighting(d);
}

#endif