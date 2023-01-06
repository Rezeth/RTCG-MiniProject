
//Guard keyword to prevent the shader graph from being compiled twice
#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

//For shadows to appear
#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#pragma multi_compile _ _SHADOWS_SOFT
#pragma multi_compile _ _ADDITIONAL_LIGHTS
#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
#pragma multi_compile _ _LIGHTMAP_SHADOW_MIXING
#pragma multi_compile _ _SHADOWS_SHADOWMASK


struct CustomLightingData {
    //Position and orientation
    float3 positionWS;
    float3 normalWS;
    float3 viewDirectionWS;
    float4 shadowCoord;

    // Surface attributes
    float3 albedo;
    float smoothness;
    float ambientOcclusion;

    //baked lighting for use to create the baked lighting maps and shadowsmask
    float3 bakedGI;
    float4 shadowMask;

};

//Translate a [0 , 1] smoothness value to an exponent
float GetSmoothnessPower(float rawSmoothness) {
    return exp2(10 * rawSmoothness + 1);
}

#ifndef SHADERGRAPH_PREVIEW
float3 CustomGlobalIllumination(CustomLightingData d) {
    //We use the bakedGI to calculate the indirrectdiffuse value stored in a float3 value.
    float3 indirectDiffuse = d.albedo * d.bakedGI * d.ambientOcclusion;

    float3 reflectVector = reflect(-d.viewDirectionWS, d.normalWS);
    // This is a rim light term, making reflections stronger along the edges of view
    float fresnel = Pow4(1 - saturate(dot(d.viewDirectionWS, d.normalWS)));
    // This function samples the baked reflections cubemap
    // It is located in URP/ShaderLibrary/Lighting.hlsl
    float3 indirectSpecular = GlossyEnvironmentReflection(reflectVector,
        RoughnessToPerceptualRoughness(1 - d.smoothness),
        d.ambientOcclusion) * fresnel;

    return indirectDiffuse * indirectSpecular;
}

float3 CustomLightHandling(CustomLightingData d, Light light) {

    float3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);

    float diffuse = saturate(dot(d.normalWS, light.direction));
    float specularDot = saturate(dot(d.normalWS, normalize(light.direction + d.viewDirectionWS)));
    float specular = pow(specularDot, GetSmoothnessPower(d.smoothness)) * diffuse;

    float3 color = d.albedo * radiance * (diffuse + specular);

    return color;

}
#endif

float3 CalculateCustomLighting(CustomLightingData d) {
#ifdef SHADERGRAPH_PREVIEW
    //In preview, estimate diffuse + specular
    float3 lightDir = float3(0.5, 0.5, 0);
    float intensity = saturate(dot(d.normalWS, lightDir)) +
        pow(saturate(dot(d.normalWS, normalize(d.viewDirectionWS + lightDir))), GetSmoothnessPower(d.smoothness));
    return d.albedo * intensity;

#else

    //Get main light to use in calculation color for the shadows and global illumination.
    Light MainLight = GetMainLight(d.shadowCoord, d.positionWS, d.shadowMask);
    // In mixed subtractive baked lights, the main light must be subtracted
    // from the bakedGI value. This function in URP/ShaderLibrary/Lighting.hlsl takes care of that.
    MixRealtimeAndBakedGI(MainLight, d.normalWS, d.bakedGI);
    float3 color = CustomGlobalIllumination(d);
    // Shade the main light
    color += CustomLightHandling(d, MainLight);
    
    #ifdef _ADDITIONAL_LIGHTS
        //shade additional cone and point lights
        uint numAdditionalLights = GetAdditionalLightsCount();
        for (uint lightI = 0; lightI < numAdditionalLights; lightI++) {
        Light light = GetAdditionalLight(lightI, d.positionWS, d.shadowMask);
        color += CustomLightHandling(d, light);
        }
#endif

    return color;
#endif
}

void CalculateCustomLighting_float(float3 Position, float3 Normal, float3 ViewDirection, float3 Albedo, float Smoothness, float AmbientOcclusion, float2 LightmapUV,
    out float3 Color) {

    CustomLightingData d;
    d.positionWS = Position;
    d.normalWS = Normal;
    d.viewDirectionWS = ViewDirection;
    d.albedo = Albedo;
    d.smoothness = Smoothness;
    d.ambientOcclusion = AmbientOcclusion;

#ifdef SHADERGRAPH_PREVIEW
    // In preview, there's no shadows for bakedGI so we need to set it equal to 0.
    d.shadowCoord = 0;
    d.bakedGI = 0;
    d.shadowMask = 0;
#else
    //Calculate the main light shadow coordinates to be used for the shadowCoord, bakedGI and shadowMask
    //there are two types depending on if cascades are enabled
    float4 positionCS = TransformWorldToHClip(Position);
    #if SHADOWS_SCREEN
        d.shadowCoord = ComputerScreenPos(positionCS);
    #else
        d.shadowCoord = TransformWorldToShadowCoord(Position);
    #endif

        // The lightmap UV is usually stored in TEXCOORD1
        // If lightmaps are disabled, OUTPUT_LIGHTMAP_UV does nothing
        float3 lightmapUV;
        OUTPUT_LIGHTMAP_UV(LightmapUV, unity_LightmapST, lightmapUV);
        // Samples spherical harmonics, which encode light probe data
        float3 vertexSH;
        OUTPUT_SH(Normal, vertexSH);
        // This function calculates the final baked lighting from light maps or probes
        d.bakedGI = SAMPLE_GI(lightmapUV, vertexSH, Normal);
        // This function calculates the shadow mask if baked shadows are enabled in the unity editor using the static checkmark.
        d.shadowMask = SAMPLE_SHADOWMASK(lightmapUV);
#endif

    Color = CalculateCustomLighting(d);
}
#endif