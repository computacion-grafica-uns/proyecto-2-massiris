Shader "Custom/CookTorranceShader_Normal"
{
    Properties
    {
        _Color      ("Color base",          Color)        = (1, 1, 1, 1)
        _BumpMap    ("Normal Map",          2D)           = "bump" {}
        _Alpha      ("Transparencia",       Range(0,1))   = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1))   = 0.03
        _Roughness  ("Rugosidad",           Range(0.01,1)) = 0.5
        // 0 = dielectrico (plastico/barro), 1 = metal
        _Metallic   ("Metalicidad",         Range(0,1))   = 0.0
        // color del reflejo especular en materiales no metalicos
        _F0         ("Reflectancia base (F0)", Color)     = (0.04, 0.04, 0.04, 1)
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        // luz direccional (forwardbase)
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4    _Color;
            sampler2D _BumpMap;
            float     _Alpha;
            float     _Ambient;
            float     _Roughness;
            float     _Metallic;
            float3    _F0;

            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                // tangente necesaria para convertir el normal map del espacio tangente al espacio del mundo
                float4 tangent : TANGENT;   // extraemos la tangente de la malla
                float2 uv      : TEXCOORD0; // coordenadas uv para samplear el normal map
            };

            struct v2f
            {
                float4 pos            : SV_POSITION;
                float3 normal         : TEXCOORD0;
                float3 worldPos       : TEXCOORD1;
                float2 uv             : TEXCOORD2; // pasamos las uv al fragment
                // componentes de la matriz tbn para transformar normales desde espacio tangente a mundo
                float3 tangentWorld   : TEXCOORD3; // tangente del vertice en espacio de mundo
                float3 bitangentWorld : TEXCOORD4; // bitangente calculada mediante el producto cruz
            };

            // funciones cook-torrance

            // d: ggx/trowbridge-reitz - distribucion de microfacetas
            float D_GGX(float NdotH, float roughness)
            {
                float a  = roughness * roughness;
                float a2 = a * a;
                float d  = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                return a2 / (UNITY_PI * d * d);
            }

            // g: smith-ggx - geometria (autooclusion de microfacetas)
            float G_Smith(float NdotV, float NdotL, float roughness)
            {
                float r  = roughness + 1.0;
                float k  = (r * r) / 8.0;
                float gV = NdotV / (NdotV * (1.0 - k) + k); // oclusion hacia la camara
                float gL = NdotL / (NdotL * (1.0 - k) + k); // oclusion hacia la luz
                return gV * gL;
            }

            // f: schlick - fresnel
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
                
                o.uv = v.uv;
                
                // construimos la matriz tbn (tangente-bitangente-normal) para cambiar de espacio
                // la tangente viene del vertex input transformada al espacio del mundo
                o.tangentWorld = UnityObjectToWorldDir(v.tangent.xyz);
                // preservamos la direccion correcta de la bitangente usando el signo de la tangente
                float tangentSign = v.tangent.w * unity_WorldTransformParams.w;
                o.bitangentWorld = cross(o.normal, o.tangentWorld) * tangentSign;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // leemos el normal map desde la textura y lo desempaquetamos
                // rango [0,1] a rango [-1,1]
                float3 tangentNormal = UnpackNormal(tex2D(_BumpMap, i.uv));
                
                // transformamos la normal del espacio tangente al espacio del mundo
                // multiplicamos cada componente de la normal por su eje correspondiente en la matriz tbn
                // tangentNormal.x * tangente + tangentNormal.y * bitangente + tangentNormal.z * normal
                float3 N = normalize(
                    tangentNormal.x * i.tangentWorld +
                    tangentNormal.y * i.bitangentWorld +
                    tangentNormal.z * normalize(i.normal)
                );

                // vectores de luz y vista
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                float NdotL = max(dot(N, L), 0.0);
                float NdotV = max(dot(N, V), 0.0);
                float NdotH = max(dot(N, H), 0.0);
                float HdotV = max(dot(H, V), 0.0);

                // f0: reflectancia en incidencia normal
                float3 f0 = lerp(_F0, _Color.rgb, _Metallic);

                // terminos cook-torrance
                float  D = D_GGX(NdotH, _Roughness);
                float  G = G_Smith(NdotV, NdotL, _Roughness);
                float3 F = F_Schlick(HdotV, f0);

                // especular pbr
                float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);

                // difuso
                float3 kS = F; // fraccion especular
                float3 kD = (1.0 - kS) * (1.0 - _Metallic); // fraccion difusa
                float3 diffuse = kD * _Color.rgb / UNITY_PI;

                // resultado final
                float3 ambient = _Ambient * _Color.rgb;
                float3 result  = ambient + (diffuse + specular) * NdotL * _LightColor0.rgb;

                float alpha = _Color.a * _Alpha;
                return fixed4(result, alpha);
            }
            ENDCG
        }

        // pass 2: luces adicionales (point y spot)
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
            sampler2D _BumpMap;
            float     _Roughness;
            float     _Metallic;
            float3    _F0;

            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                // tangente necesaria para convertir el normal map del espacio tangente al espacio del mundo
                float4 tangent : TANGENT;
                float2 uv      : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos            : SV_POSITION;
                float3 normal         : TEXCOORD0;
                float3 worldPos       : TEXCOORD1;
                float2 uv             : TEXCOORD2;
                // componentes de la matriz tbn para transformar normales desde espacio tangente a mundo
                float3 tangentWorld   : TEXCOORD3;
                float3 bitangentWorld : TEXCOORD4;
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
                
                o.uv = v.uv;
                
                // construimos la matriz tbn (tangente-bitangente-normal) para cambiar de espacio
                // la tangente viene del vertex input transformada al espacio del mundo
                o.tangentWorld = UnityObjectToWorldDir(v.tangent.xyz);
                // preservamos la direccion correcta de la bitangente usando el signo de la tangente
                float tangentSign = v.tangent.w * unity_WorldTransformParams.w;
                o.bitangentWorld = cross(o.normal, o.tangentWorld) * tangentSign;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // leemos el normal map desde la textura y lo desempaquetamos
                // rango [0,1] a rango [-1,1]
                float3 tangentNormal = UnpackNormal(tex2D(_BumpMap, i.uv));
                
                // transformamos la normal del espacio tangente al espacio del mundo
                // multiplicamos cada componente de la normal por su eje correspondiente en la matriz tbn
                // tangentNormal.x * tangente + tangentNormal.y * bitangente + tangentNormal.z * normal
                float3 N = normalize(
                    tangentNormal.x * i.tangentWorld +
                    tangentNormal.y * i.bitangentWorld +
                    tangentNormal.z * normalize(i.normal)
                );

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

                float3 result = (diffuse + specular) * NdotL * _LightColor0.rgb * atten;

                // las luces adicionales no modifican el alpha
                return fixed4(result, 1.0);
            }
            ENDCG
        }
    }
}