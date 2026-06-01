Shader "Custom/ToonShader_Normal"
{
    Properties
    {
        _Color      ("Color base",          Color)      = (0.6, 0.3, 0.15, 1)
        _Alpha      ("Transparencia",       Range(0,1)) = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1)) = 0.2
        _Diffuse    ("Intensidad difusa",   Range(0,1)) = 0.8
        _Specular   ("Intensidad especular",Range(0,1)) = 0.3
        _Shininess  ("Brillo especular",    Range(1,256)) = 16

        // nueva propiedad para el mapa de normales
        _BumpMap    ("Mapa de normales",    2D)         = "bump" {}

        // Propiedades toon
        _DiffuseBands   ("Bandas difusas",    Range(1,8))   = 3
        _SpecularThresh ("Umbral especular",  Range(0,1))   = 0.5
        _SpecularSmooth ("Suavidad especular",Range(0,0.1)) = 0.02

        // Outline
        _OutlineColor   ("Color del contorno", Color)      = (0,0,0,1)
        _OutlineWidth   ("Grosor del contorno", Range(0, 0.1)) = 0.02
    }

    SubShader
    {
        Tags { "Queue"="Geometry" }

        // Pass 0 outline (LLM)
        Pass
        {
            Name "OUTLINE"
            Cull Front
            ZWrite On

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed4 _OutlineColor;
            float  _OutlineWidth;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                float3 worldNorm = UnityObjectToWorldNormal(v.normal);
                float4 worldPos  = mul(unity_ObjectToWorld, v.vertex);
                worldPos.xyz    += worldNorm * _OutlineWidth;
                o.pos = mul(UNITY_MATRIX_VP, worldPos);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                return _OutlineColor;
            }
            ENDCG
        }

        // Pass 1: Iluminacion toon (ForwardBase) 
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            ZWrite On

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4  _Color;
            float   _Alpha;
            float   _Ambient;
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;
            float   _DiffuseBands;
            float   _SpecularThresh;
            float   _SpecularSmooth;
            
            // variable para la textura
            sampler2D _BumpMap;
            float4 _BumpMap_ST;

            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                // pedimos las uv y la tangente al modelo
                float2 uv      : TEXCOORD0;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos        : SV_POSITION;
                float3 worldPos   : TEXCOORD0;
                // variables para pasar vectores al fragment shader
                float2 uv         : TEXCOORD1;
                float3 normalW    : TEXCOORD2;
                float3 tangentW   : TEXCOORD3;
                float3 bitangentW : TEXCOORD4;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                
                // pasamos las uv modificadas por tiling/offset
                o.uv = TRANSFORM_TEX(v.uv, _BumpMap);

                // calculamos vectores en el mundo
                o.normalW  = UnityObjectToWorldNormal(v.normal);
                o.tangentW = UnityObjectToWorldDir(v.tangent.xyz);
                
                // sacamos la bitangente multiplicando normal y tangente
                float signo = v.tangent.w * unity_WorldTransformParams.w;
                o.bitangentW = cross(o.normalW, o.tangentW) * signo;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // leemos el color del pixel en el mapa de normales
                float3 normalTextura = UnpackNormal(tex2D(_BumpMap, i.uv));

                // armamos nuestra matriz tbn
                float3x3 tbn = float3x3(i.tangentW, i.bitangentW, i.normalW);

                // convertimos la normal al mundo real
                float3 N = normalize(mul(normalTextura, tbn));
                
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                // componente ambiental
                float3 ambient = _Ambient * _Color.rgb;

                // difusa cuantizada usando la nueva normal
                float diff = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * _LightColor0.rgb;

                // especular binaria
                float spec = pow(max(dot(N, H), 0.0), _Shininess);
                float specToon = smoothstep(
                    _SpecularThresh - _SpecularSmooth,
                    _SpecularThresh + _SpecularSmooth,
                    spec
                );
                float3 specular = _Specular * specToon * _LightColor0.rgb;

                float3 result = ambient + diffuse + specular;
                return fixed4(result, 1.0);
            }
            ENDCG
        }

        // Pass 2: Luces adicionales (ForwardAdd)
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

            fixed4  _Color;
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;
            float   _DiffuseBands;
            float   _SpecularThresh;
            float   _SpecularSmooth;
            
            sampler2D _BumpMap;
            float4 _BumpMap_ST;

            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                float2 uv      : TEXCOORD0;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos        : SV_POSITION;
                float3 worldPos   : TEXCOORD0;
                float2 uv         : TEXCOORD1;
                float3 normalW    : TEXCOORD2;
                float3 tangentW   : TEXCOORD3;
                float3 bitangentW : TEXCOORD4;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                
                o.uv = TRANSFORM_TEX(v.uv, _BumpMap);

                o.normalW  = UnityObjectToWorldNormal(v.normal);
                o.tangentW = UnityObjectToWorldDir(v.tangent.xyz);
                
                float signo = v.tangent.w * unity_WorldTransformParams.w;
                o.bitangentW = cross(o.normalW, o.tangentW) * signo;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // repetimos la lectura de la normal
                float3 normalTextura = UnpackNormal(tex2D(_BumpMap, i.uv));
                float3x3 tbn = float3x3(i.tangentW, i.bitangentW, i.normalW);
                float3 N = normalize(mul(normalTextura, tbn));

                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);

                #ifdef USING_DIRECTIONAL_LIGHT
                    float3 L = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    float3 L = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
                #endif

                float3 H = normalize(L + V);

                // usamos la normal calculada para las luces secundarias
                float diff     = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * _LightColor0.rgb;

                float spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float specToon = smoothstep(
                    _SpecularThresh - _SpecularSmooth,
                    _SpecularThresh + _SpecularSmooth,
                    spec
                );
                float3 specular = _Specular * specToon * _LightColor0.rgb;

                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                return fixed4((diffuse + specular) * atten, 1.0);
            }
            ENDCG
        }
    }
}