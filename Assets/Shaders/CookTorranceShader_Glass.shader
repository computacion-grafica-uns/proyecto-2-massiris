Shader "Custom/CookTorranceShader_Glass"
{
    Properties
    {
        _Color      ("Color base",          Color)        = (1, 1, 1, 1)
        _Alpha      ("Transparencia",       Range(0,1))   = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1))   = 0.03
        _Roughness  ("Rugosidad",           Range(0.01,1)) = 0.5
        // 0 = dielectrico (plastico/barro), 1 = metal
        _Metallic   ("Metalicidad",         Range(0,1))   = 0.0
        // Color del reflejo especular en materiales no metalicos
        _F0         ("Reflectancia base (F0)", Color)     = (0.04, 0.04, 0.04, 1)
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        // CAMBIO 1: Alpha Premultiplicado para que el especular siga siendo brillante
        Blend One OneMinusSrcAlpha
        ZWrite Off
        // pre-z pass (llm) solucion a orden de dibujo incorrecto
        Pass
        {
            ColorMask 0        // no escribe ningun canal de color (r, g, b, a)
            ZWrite On          // solo nos importa escribir el depth buffer
        }
        //  Pass 1: luz direccional (ForwardBase)
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

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            //  Funciones Cook-Torrance
            float D_GGX(float NdotH, float roughness)
            {
                float a  = roughness * roughness;
                float a2 = a * a;
                float d  = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                return a2 / (UNITY_PI * d * d);
            }

            float G_Smith(float NdotV, float NdotL, float roughness)
            {
                float r  = roughness + 1.0;
                float k  = (r * r) / 8.0;
                float gV = NdotV / (NdotV * (1.0 - k) + k);
                float gL = NdotL / (NdotL * (1.0 - k) + k);
                return gV * gL;
            }

            float3 F_Schlick(float HdotV, float3 f0)
            {
                return f0 + (1.0 - f0) * pow(1.0 - HdotV, 5.0);
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                float NdotL = max(dot(N, L), 0.0);
                float NdotV = max(dot(N, V), 0.0);
                float NdotH = max(dot(N, H), 0.0);
                float HdotV = max(dot(H, V), 0.0);

                float3 f0 = lerp(_F0, _Color.rgb, _Metallic);
                
                float  D = D_GGX(NdotH, _Roughness);
                float  G = G_Smith(NdotV, NdotL, _Roughness);
                float3 F = F_Schlick(HdotV, f0);

                float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);
                
                float3 kS = F;
                float3 kD = (1.0 - kS) * (1.0 - _Metallic);
                float3 diffuse = kD * _Color.rgb / UNITY_PI;

                // CAMBIO 2: Calculamos el alpha y lo aplicamos SOLO al difuso y al ambiente.
                float alpha = _Color.a * _Alpha;
                float3 premulDiffuse = diffuse * alpha;
                float3 premulAmbient = (_Ambient * _Color.rgb) * alpha;

                // Sumamos el especular puro para que brille aunque el material sea transparente
                float3 result = premulAmbient + (premulDiffuse + specular) * NdotL * _LightColor0.rgb;

                return fixed4(result, alpha);
            }
            ENDCG
        }

        //  Pass 2: luces adicionales (point y spot)
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
            float     _Alpha; // CAMBIO 3: Agregada la variable _Alpha que faltaba en este Pass
            float     _Roughness;
            float     _Metallic;
            float3    _F0;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            float D_GGX(float NdotH, float roughness)
            {
                float a  = roughness * roughness;
                float a2 = a * a;
                float d  = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                return a2 / (UNITY_PI * d * d);
            }

            float G_Smith(float NdotV, float NdotL, float roughness)
            {
                float r  = roughness + 1.0;
                float k  = (r * r) / 8.0;
                float gV = NdotV / (NdotV * (1.0 - k) + k);
                float gL = NdotL / (NdotL * (1.0 - k) + k);
                return gV * gL;
            }

            float3 F_Schlick(float HdotV, float3 f0)
            {
                return f0 + (1.0 - f0) * pow(1.0 - HdotV, 5.0);
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
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

                float3 f0 = lerp(_F0, _Color.rgb, _Metallic);

                float  D = D_GGX(NdotH, _Roughness);
                float  G = G_Smith(NdotV, NdotL, _Roughness);
                float3 F = F_Schlick(HdotV, f0);
                
                float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);
                
                float3 kS = F;
                float3 kD = (1.0 - kS) * (1.0 - _Metallic);
                float3 diffuse = kD * _Color.rgb / UNITY_PI;
                
                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                // CAMBIO 4: Multiplicamos el difuso por alpha antes de sumar el especular
                float alpha = _Color.a * _Alpha;
                float3 premulDiffuse = diffuse * alpha;

                float3 result = (premulDiffuse + specular) * NdotL * _LightColor0.rgb * atten;
                
                return fixed4(result, 1.0);
            }
            ENDCG
        }
    }
}