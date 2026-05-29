Shader "Custom/CookTorranceShader_Glass"
{
    //no voy a negar las refracciones y reflejos fueron hechos con ayuda LLMs
    Properties
    {
        _Color      ("Tinte del cristal",   Color)        = (1, 1, 1, 0.1)
        _Distortion ("Fuerza de refracción", Range(0, 0.5)) = 0.05
        _Roughness  ("Rugosidad",           Range(0.01, 1)) = 0.02 // El cristal suele ser muy liso
        _Metallic   ("Metalicidad",         Range(0, 1))  = 0.0    // El cristal es dieléctrico (0)
        _F0         ("Reflectancia (F0)",   Color)        = (0.04, 0.04, 0.04, 1)
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        
        // ── GrabPass: Captura la pantalla detrás del objeto ─────────────
        GrabPass { "_RefractionTex" }

        // Como nosotros calculamos la transparencia y el fondo manualmente 
        // en el shader, renderizamos esto como si fuera opaco (1.0 alpha)
        Blend One Zero
        ZWrite Off

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            sampler2D _RefractionTex;
            fixed4    _Color;
            float     _Distortion;
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
                float4 grabPos  : TEXCOORD2; // Coordenadas para la refracción
            };

            // ── Funciones Cook-Torrance ────────────────────────────────────

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
                
                // Calcula la posición en pantalla para el GrabPass
                o.grabPos  = ComputeGrabScreenPos(o.pos);
                
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // Vectores
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                float NdotL = max(dot(N, L), 0.0);
                float NdotV = max(dot(N, V), 0.0);
                float NdotH = max(dot(N, H), 0.0);
                float HdotV = max(dot(H, V), 0.0);

                // ── Refracción (Fondo distorsionado) ──────────────────────
                // Usamos las normales (N.xy) para doblar las coordenadas UV del fondo
                float2 offset = N.xy * _Distortion;
                float2 grabUV = (i.grabPos.xy / i.grabPos.w) + offset;
                float3 bgColor = tex2D(_RefractionTex, grabUV).rgb;

                // Mezclamos el fondo refractado con el tinte del cristal
                // Si _Color.a es 0, es cristal puro. Si es 1, toma el color sólido.
                float3 refractionColor = lerp(bgColor, _Color.rgb * bgColor, _Color.a);

                // ── Especular Cook-Torrance ───────────────────────────────
                float3 f0 = lerp(_F0, _Color.rgb, _Metallic);
                float  D = D_GGX(NdotH, _Roughness);
                float  G = G_Smith(NdotV, NdotL, _Roughness);
                float3 F = F_Schlick(HdotV, f0);

                float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);

                // ── Resultado final ───────────────────────────────────────
                // El cristal dieléctrico perfecto no tiene luz difusa Lambertiana.
                // Todo es refracción del fondo + reflejos de la luz.
                
                float3 finalColor = refractionColor + (specular * NdotL * _LightColor0.rgb);

                // Devolvemos 1.0 en alpha porque ya simulamos la transparencia
                // internamente al pintar el fondo (bgColor) directamente en el modelo.
                return fixed4(finalColor, 1.0);
            }
            ENDCG
        }
    }
}