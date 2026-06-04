Shader "Custom/ToonShader_Procedural"
{
    Properties
    {
        _Color      ("Color base",          Color)      = (0.6, 0.3, 0.15, 1)
        _Alpha      ("Transparencia",       Range(0,1)) = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1)) = 0.2
        _Diffuse    ("Intensidad difusa",   Range(0,1)) = 0.8
        _Specular   ("Intensidad especular",Range(0,1)) = 0.3
        _Shininess  ("Brillo especular",    Range(1,256)) = 16

        // propiedades toon
        _DiffuseBands   ("Bandas difusas",    Range(1,8))   = 3
        _SpecularThresh ("Umbral especular",  Range(0,1))   = 0.5
        _SpecularSmooth ("Suavidad especular",Range(0,0.1)) = 0.02

        // outline
        _OutlineColor   ("Color del contorno", Color)      = (0,0,0,1)
        _OutlineWidth   ("Grosor del contorno", Range(0, 0.1)) = 0.02

        // textura procedural
        // frecuencia de las rayas (mas alto = rayas mas juntas)
        _HatchFreq      ("Frecuencia de rayas", Range(1, 50)) = 10
        // que tan oscuro se pone el hatch (0 = invisible, 1 = negro)
        _HatchStrength  ("Intensidad de rayas", Range(0, 1))  = 0.4
        // hasta que nivel de luz aparecen las rayas (umbral de sombra)
        _HatchThresh    ("Umbral de sombra",    Range(0, 1))  = 0.4
    }

    SubShader
    {
        Tags { "Queue"="Geometry" }
        // pre-z pass (llm) solucion a orden de dibujo incorrecto
        Pass
        {
            ColorMask 0        // no escribe ningun canal de color (r, g, b, a)
            ZWrite On          // solo nos importa escribir el depth buffer
        }
        // pass 0: outline (caras traseras agrandadas en direccion a la normal)
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

        // pass 1: iluminacion toon (luz principal / ForwardBase)
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

            // variables del hatch
            float   _HatchFreq;
            float   _HatchStrength;
            float   _HatchThresh;

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

            // funcion de textura procedural
            // genera rayas diagonales usando la posicion world.
            // devuelve 1 donde hay raya, 0 donde no.
            float hatch(float3 worldPos, float freq)
            {
                // sumamos x+y para que las rayas sean diagonales a 45 grados
                float stripe = sin((worldPos.x + worldPos.y) * freq * 3.14159);
                // step convierte la onda continua en 0 o 1 (patron binario)
                return step(0.0, stripe);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                // componente ambiental
                float3 ambient = _Ambient * _Color.rgb;

                // difusa cuantizada en bandas
                float diff     = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * _LightColor0.rgb;

                // especular binaria con borde suave
                float spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float specToon = smoothstep(
                    _SpecularThresh - _SpecularSmooth,
                    _SpecularThresh + _SpecularSmooth,
                    spec
                );
                float3 specular = _Specular * specToon * _LightColor0.rgb;

                // aplicacion del hatch
                // solo aparece en zonas de sombra (diff < umbral)
                // shadowMask vale 1 en las partes oscuras, 0 en las claras
                float shadowMask = step(diff, _HatchThresh);

                // generamos el patron de rayas
                float hatchVal = hatch(i.worldPos, _HatchFreq);

                // oscurecemos el color base donde hay raya Y hay sombra
                float3 hatchColor = _Color.rgb * (1.0 - _HatchStrength * hatchVal * shadowMask);

                // reemplazamos el aporte del color base en ambient+diffuse con el hatch
                float3 result = ambient * hatchColor / max(_Color.rgb, 0.001)
                              + _Diffuse * diffToon * hatchColor * _LightColor0.rgb
                              + specular;
                return fixed4(result, 1.0);
            }
            ENDCG
        }

        // pass 2: luces adicionales (point y spot) / ForwardAdd
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

                // difusa cuantizada
                float diff     = max(dot(N, L), 0.0);
                float diffToon = floor(diff * _DiffuseBands) / _DiffuseBands;
                float3 diffuse = _Diffuse * diffToon * _Color.rgb * _LightColor0.rgb;

                // especular binaria con suavizado
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
