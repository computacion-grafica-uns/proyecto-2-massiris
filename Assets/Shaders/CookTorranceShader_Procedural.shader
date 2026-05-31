Shader "Custom/CookTorranceShader_Procedural"
{
    Properties
    {
        _Color      ("Color base (Madera Clara)", Color)  = (0.6, 0.4, 0.2, 1)
        _Color2     ("Color vetas (Madera Oscura)",Color) = (0.3, 0.15, 0.05, 1)
        _Alpha      ("Transparencia",       Range(0,1))   = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1))   = 0.03
        _Roughness  ("Rugosidad",           Range(0.01,1)) = 0.5
        _Metallic   ("Metalicidad",         Range(0,1))   = 0.0
        _F0         ("Reflectancia base (F0)", Color)     = (0.04, 0.04, 0.04, 1)
        
        // Controles Procedurales
        _NoiseScale ("Escala del Ruido",    Float)        = 10.0
        _RingScale  ("Densidad de Anillos", Float)        = 20.0
        _Turbulence ("Turbulencia",         Float)        = 2.0
    }

    // Bloque común para no repetir funciones de ruido en ambos pases
    CGINCLUDE
    float _NoiseScale;
    float _RingScale;
    float _Turbulence;
    fixed4 _Color2;

    // Función Hash 3D
    float hash(float3 p) {
        p = frac(p * 0.3183099 + 0.1);
        p *= 17.0;
        return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
    }

    // Función de Ruido de Valor 3D básico
    float noise(float3 x) {
        float3 i = floor(x);
        float3 f = frac(x);
        f = f * f * (3.0 - 2.0 * f);

        return lerp(lerp(lerp(hash(i + float3(0,0,0)), hash(i + float3(1,0,0)), f.x),
                         lerp(hash(i + float3(0,1,0)), hash(i + float3(1,1,0)), f.x), f.y),
                    lerp(lerp(hash(i + float3(0,0,1)), hash(i + float3(1,0,1)), f.x),
                         lerp(hash(i + float3(0,1,1)), hash(i + float3(1,1,1)), f.x), f.y), f.z);
    }

    // Expresión para calcular el color procedural de la madera
    float3 GetWoodAlbedo(float3 worldPos, float3 color1, float3 color2) {
        // Generar ruido tridimensional basado en la posición del mundo
        float n = noise(worldPos * _NoiseScale);
        
        // Calcular la distancia desde el eje Y central (asumiendo que el árbol crece en Y)
        // Puedes cambiar esto a length(worldPos) para un patrón esférico tipo mármol/granito.
        float radius = length(worldPos.xz);
        
        // Aplicar la distorsión senoidal
        float woodPattern = sin(radius * _RingScale + n * _Turbulence);
        
        // Normalizar de [-1, 1] a [0, 1]
        woodPattern = woodPattern * 0.5 + 0.5;
        
        // Interpolar entre los dos colores de madera
        return lerp(color1, color2, woodPattern);
    }
    ENDCG

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        // --- Pase 1: Luz Direccional (ForwardBase) ---
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4    _Color;
            float     _Alpha;
            float     _Ambient;
            float     _Roughness;
            float     _Metallic;
            float3    _F0;

            struct appdata {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            // Funciones Cook-Torrance
            float D_GGX(float NdotH, float roughness) {
                float a = roughness * roughness;
                float a2 = a * a;
                float d = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                return a2 / (UNITY_PI * d * d);
            }

            float G_Smith(float NdotV, float NdotL, float roughness) {
                float r = roughness + 1.0;
                float k = (r * r) / 8.0;
                float gV = NdotV / (NdotV * (1.0 - k) + k);
                float gL = NdotL / (NdotL * (1.0 - k) + k);
                return gV * gL;
            }

            float3 F_Schlick(float HdotV, float3 f0) {
                return f0 + (1.0 - f0) * pow(1.0 - HdotV, 5.0);
            }

            v2f vert(appdata v) {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target {
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                float NdotL = max(dot(N, L), 0.0);
                float NdotV = max(dot(N, V), 0.0);
                float NdotH = max(dot(N, H), 0.0);
                float HdotV = max(dot(H, V), 0.0);

                // --- INTEGRACIÓN PROCEDURAL ---
                // Reemplazamos _Color.rgb con nuestro albedo calculado en tiempo real
                float3 albedo = GetWoodAlbedo(i.worldPos, _Color.rgb, _Color2.rgb);

                float3 f0 = lerp(_F0, albedo, _Metallic);

                float D = D_GGX(NdotH, _Roughness);
                float G = G_Smith(NdotV, NdotL, _Roughness);
                float3 F = F_Schlick(HdotV, f0);

                float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);

                float3 kS = F;
                float3 kD = (1.0 - kS) * (1.0 - _Metallic);
                
                // Aplicamos el albedo procedural al término difuso y ambiente
                float3 diffuse = kD * albedo / UNITY_PI;
                float3 ambient = _Ambient * albedo;
                float3 result  = ambient + (diffuse + specular) * NdotL * _LightColor0.rgb;

                float alpha = _Color.a * _Alpha;
                return fixed4(result, alpha);
            }
            ENDCG
        }

        // --- Pase 2: Luces adicionales (ForwardAdd) ---
        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            Blend One One
            ZWrite Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdadd
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            fixed4    _Color;
            float     _Roughness;
            float     _Metallic;
            float3    _F0;

            struct appdata {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            float D_GGX(float NdotH, float roughness) {
                float a = roughness * roughness;
                float a2 = a * a;
                float d = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                return a2 / (UNITY_PI * d * d);
            }

            float G_Smith(float NdotV, float NdotL, float roughness) {
                float r = roughness + 1.0;
                float k = (r * r) / 8.0;
                float gV = NdotV / (NdotV * (1.0 - k) + k);
                float gL = NdotL / (NdotL * (1.0 - k) + k);
                return gV * gL;
            }

            float3 F_Schlick(float HdotV, float3 f0) {
                return f0 + (1.0 - f0) * pow(1.0 - HdotV, 5.0);
            }

            v2f vert(appdata v) {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target {
                float3 N = normalize(i.normal);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);

                #ifdef USING_DIRECTIONAL_LIGHT
                    float3 L = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    float3 L = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
                #endif

                float3 H = normalize(L + V);
                float NdotL = max(dot(N, L), 0.0);
                float NdotV = max(dot(N, V), 0.0);
                float NdotH = max(dot(N, H), 0.0);
                float HdotV = max(dot(H, V), 0.0);

                // --- INTEGRACIÓN PROCEDURAL ---
                float3 albedo = GetWoodAlbedo(i.worldPos, _Color.rgb, _Color2.rgb);

                float3 f0 = lerp(_F0, albedo, _Metallic);

                float D = D_GGX(NdotH, _Roughness);
                float G = G_Smith(NdotV, NdotL, _Roughness);
                float3 F = F_Schlick(HdotV, f0);

                float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);

                float3 kS = F;
                float3 kD = (1.0 - kS) * (1.0 - _Metallic);
                
                float3 diffuse = kD * albedo / UNITY_PI;
                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                float3 result = (diffuse + specular) * NdotL * _LightColor0.rgb * atten;
                return fixed4(result, 1.0);
            }
            ENDCG
        }
    }
}