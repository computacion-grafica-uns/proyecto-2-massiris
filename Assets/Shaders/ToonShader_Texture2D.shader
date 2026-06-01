Shader "Custom/ToonShader_Texture2D"
{
    Properties
    {
        _Color      ("color base",          Color)      = (0.6, 0.3, 0.15, 1)
        _MainTex    ("textura 2d",          2D)         = "white" {}
        _Alpha      ("transparencia",       Range(0,1)) = 1.0
        _Ambient    ("intensidad ambiente", Range(0,1)) = 0.2
        _Diffuse    ("intensidad difusa",   Range(0,1)) = 0.8
        _Specular   ("intensidad especular",Range(0,1)) = 0.3
        _Shininess  ("brillo especular",    Range(1,256)) = 16

        // propiedades toon
        _DiffuseBands   ("bandas difusas",    Range(1,8))   = 3
        _SpecularThresh ("umbral especular",  Range(0,1))   = 0.5
        _SpecularSmooth ("suavidad especular",Range(0,0.1)) = 0.02

        // contorno
        _OutlineColor   ("color del contorno", Color)      = (0,0,0,1)
        _OutlineWidth   ("grosor del contorno", Range(0, 0.1)) = 0.02
    }

    SubShader
    {
        Tags { "Queue"="Geometry" }

        // pass 0 contorno
        // dibujamos las caras de atras mas grandes siguiendo la normal
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
                // movemos cada vertice hacia afuera usando su normal
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

        // pass 1: iluminacion toon con luz principal
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
            sampler2D _MainTex;
            float4  _MainTex_ST;
            
            float   _Alpha;
            float   _Ambient;
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;
            float   _DiffuseBands;
            float   _SpecularThresh;
            float   _SpecularSmooth;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0; // recibe las coordenadas de la textura
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float2 uv       : TEXCOORD2; // pasa las coordenadas al fragment shader
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                o.uv       = TRANSFORM_TEX(v.uv, _MainTex); // calcula la posicion de la textura
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                // leemos el color de la textura en este pixel
                fixed4 texColor = tex2D(_MainTex, i.uv);

                // luz ambiente combinada con la textura
                float3 ambient = _Ambient * _Color.rgb * texColor.rgb;

                // luz difusa en escalones combinada con la textura
                float diff = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * texColor.rgb * _LightColor0.rgb;

                // luz especular cortada
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

        // pass 2: luces adicionales como puntuales o focos
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
            sampler2D _MainTex;
            float4  _MainTex_ST;
            
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;
            float   _DiffuseBands;
            float   _SpecularThresh;
            float   _SpecularSmooth;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0; // nuevo para luces adicionales
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float2 uv       : TEXCOORD2; // nuevo para luces adicionales
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                o.uv       = TRANSFORM_TEX(v.uv, _MainTex); // nuevo para luces adicionales
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

                // leemos la textura para las luces extra
                fixed4 texColor = tex2D(_MainTex, i.uv);

                // luz difusa en escalones con textura
                float diff     = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * texColor.rgb * _LightColor0.rgb;

                // luz especular binaria con suavizado
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