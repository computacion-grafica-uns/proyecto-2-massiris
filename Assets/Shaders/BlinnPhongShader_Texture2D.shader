Shader "Custom/BlinnPhongShader_Texture2D"
{
    Properties
    {
        _MainTex    ("Textura base",        2D)         = "white" {}
        _Color      ("Color base",          Color)      = (0.6, 0.3, 0.15, 1)
        _Alpha      ("Transparencia",       Range(0,1)) = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1)) = 0.2
        _Diffuse    ("Intensidad difusa",   Range(0,1)) = 0.8
        _Specular   ("Intensidad especular",Range(0,1)) = 0.3
        _Shininess  ("Brillo especular",    Range(1,256)) = 16
    }

    SubShader
    {
        Tags { "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        // ── Pass 1: luz direccional (ForwardBase) ──────────────────────────
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            // Variables que vienen de Properties
            sampler2D _MainTex;
            float4    _MainTex_ST;  // escala y offset (Tiling/Offset del Inspector)
            fixed4    _Color;
            float     _Alpha;
            float     _Ambient;
            float     _Diffuse;
            float     _Specular;
            float     _Shininess;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;  // UVs del mesh
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;    // normal en world space
                float3 worldPos : TEXCOORD1;    // posicion en world space
                float2 uv       : TEXCOORD2;    // UVs interpoladas al fragment
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                // TRANSFORM_TEX aplica el Tiling y Offset configurados en el Inspector
                o.uv       = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // ── Mapeo 2D Directo ──────────────────────────────────────
                // Las UVs vienen directamente del mesh (sin modificar).
                // tex2D samplea la textura en esa coordenada y la tintamos con _Color.
                fixed4 texColor = tex2D(_MainTex, i.uv) * _Color;

                // Normalizamos los vectores
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);  // vector medio (Blinn-Phong)

                // Componente ambiental
                float3 ambient  = _Ambient * texColor.rgb;

                // Componente difusa
                float  diff    = max(dot(N, L), 0.0);
                float3 diffuse = _Diffuse * diff * texColor.rgb * _LightColor0.rgb;

                // Componente especular (Blinn-Phong)
                float  spec    = pow(max(dot(N, H), 0.0), _Shininess);
                float3 specular = _Specular * spec * _LightColor0.rgb;

                float3 result = ambient + diffuse + specular;
                float  alpha  = texColor.a * _Alpha;
                return fixed4(result, alpha);
            }
            ENDCG
        }

        // ── Pass 2: luces adicionales (point y spot) ───────────────────────
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

            sampler2D _MainTex;
            float4    _MainTex_ST;
            fixed4    _Color;
            float     _Diffuse;
            float     _Specular;
            float     _Shininess;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float2 uv       : TEXCOORD2;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal   = UnityObjectToWorldNormal(v.normal);
                o.uv       = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // ── Mapeo 2D Directo ──────────────────────────────────────
                fixed4 texColor = tex2D(_MainTex, i.uv) * _Color;

                float3 N = normalize(i.normal);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);

                // Para point y spot la dirección de la luz se calcula diferente
                #ifdef USING_DIRECTIONAL_LIGHT
                    float3 L = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    float3 L = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
                #endif

                float3 H = normalize(L + V);

                float  diff     = max(dot(N, L), 0.0);
                float3 diffuse  = _Diffuse  * diff * texColor.rgb * _LightColor0.rgb;
                float  spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float3 specular = _Specular * spec  * _LightColor0.rgb;

                // Atenuación (point y spot se apagan con la distancia)
                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                return fixed4((diffuse + specular) * atten, 1.0);
            }
            ENDCG
        }
    }
}
