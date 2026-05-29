Shader "Custom/ToonShader"
{
    Properties
    {
        _Color      ("Color base",          Color)      = (0.6, 0.3, 0.15, 1)
        _Alpha      ("Transparencia",       Range(0,1)) = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1)) = 0.2
        _Diffuse    ("Intensidad difusa",   Range(0,1)) = 0.8
        _Specular   ("Intensidad especular",Range(0,1)) = 0.3
        _Shininess  ("Brillo especular",    Range(1,256)) = 16

        // Propiedades nuevas del estilo toon
        _DiffuseBands   ("Bandas difusas",    Range(1,8))   = 3
        _SpecularThresh ("Umbral especular",  Range(0,1))   = 0.5
        _SpecularSmooth ("Suavidad especular",Range(0,0.1)) = 0.02

        // Outline (contorno negro)
        _OutlineColor   ("Color del contorno", Color)      = (0,0,0,1)
        _OutlineWidth   ("Grosor del contorno", Range(0, 0.1)) = 0.02
    }

    SubShader
    {
        Tags { "Queue"="Transparent" }

        // ─── Pass 0: Outline (contorno negro) ───────────────────────────────
        // Truco clásico: renderizamos solo las caras traseras, agrandadas
        // en dirección a la normal, con color negro.
        Pass
        {
            Name "OUTLINE"
            Cull Front          // dibujamos la cara trasera del mesh
            ZWrite On
            Blend SrcAlpha OneMinusSrcAlpha

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
                // Desplazamos cada vértice hacia afuera a lo largo de su normal
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

        // ─── Pass 1: Iluminación toon (luz principal / ForwardBase) ─────────
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off

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

                // ── Componente ambiental (sin cambios) ──
                float3 ambient = _Ambient * _Color.rgb;

                // ── Difusa CUANTIZADA ───────────────────
                // En vez de usar diff directamente, lo "escalamos" a bandas
                // floor(diff * bandas) / bandas da escalones de igual ancho
                float diff = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * _LightColor0.rgb;

                // ── Especular BINARIA ───────────────────
                // En toon la especular es on/off: aparece cuando supera un umbral.
                // smoothstep da un borde suave (evita aliasing en el filo).
                float spec = pow(max(dot(N, H), 0.0), _Shininess);
                float specToon = smoothstep(
                    _SpecularThresh - _SpecularSmooth,
                    _SpecularThresh + _SpecularSmooth,
                    spec
                );
                float3 specular = _Specular * specToon * _LightColor0.rgb;

                float3 result = ambient + diffuse + specular;
                float  alpha  = _Color.a * _Alpha;
                return fixed4(result, alpha);
            }
            ENDCG
        }

        // ─── Pass 2: Luces adicionales (point y spot) / ForwardAdd ──────────
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

                // Difusa cuantizada
                float diff     = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * _LightColor0.rgb;

                // Especular binaria con suavizado
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
