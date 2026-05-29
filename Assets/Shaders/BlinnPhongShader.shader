Shader "Custom/BlinnPhongShader"
{
    Properties
    {
        _Color      ("Color base",        Color)  = (0.6, 0.3, 0.15, 1)
        _Alpha      ("Transparencia",     Range(0,1)) = 1.0
        _Ambient    ("Intensidad ambiente", Range(0,1)) = 0.2
        _Diffuse    ("Intensidad difusa",   Range(0,1)) = 0.8
        _Specular   ("Intensidad especular",Range(0,1)) = 0.3
        _Shininess  ("Brillo especular",    Range(1,256)) = 16
    }

    SubShader
    {
        Tags { "Queue"="Transparent" } //unity usa esta etiqueta para ordenar los objetos transparentes después de los opacos
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            // Variables que vienen de Properties
            fixed4  _Color;
            float   _Alpha;
            float   _Ambient;
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos    : SV_POSITION;
                float3 normal : TEXCOORD0;   // normal en world space
                float3 worldPos : TEXCOORD1; // posicion en world space
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
                // Normalizamos los vectores
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);  // direccion a la luz
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos); // direccion a la cámara
                float3 H = normalize(L + V);  // vector medio (Blinn-Phong)

                // Componente ambiental
                float3 ambient = _Ambient * _Color.rgb;

                // Componente difusa
                float diff = max(dot(N, L), 0.0);
                float3 diffuse = _Diffuse * diff * _Color.rgb * _LightColor0.rgb;

                // Componente especular (Blinn-Phong)
                float spec = pow(max(dot(N, H), 0.0), _Shininess); //producto punto de los vectores normal y medio elevado al brillo
                // si el producto punto es negativo, no hay componente especular es decir 0

                float3 specular = _Specular * spec * _LightColor0.rgb;

                float3 result = ambient + diffuse + specular;
                float alpha = _Color.a * _Alpha;  // Combina el alpha del color con el control de transparencia
                return fixed4(result, alpha); //generamos un vector de 4 componentes (RGB + Alpha) para el color final del fragmento
            }
            ENDCG
        }

        // Segundo pass: acumula las luces adicionales (point y spot)
        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            Blend One One          // suma la contribución de cada luz extra
            ZWrite Off             // no sobreescribe el depth buffer

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdadd   // genera variantes para point y spot
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            fixed4  _Color;
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;

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

                // Para point y spot la dirección de la luz se calcula diferente
                #ifdef USING_DIRECTIONAL_LIGHT
                    float3 L = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    float3 L = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
                #endif

                float3 H = normalize(L + V);

                float  diff     = max(dot(N, L), 0.0);
                float3 diffuse  = _Diffuse * diff * _Color.rgb * _LightColor0.rgb;
                float  spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float3 specular = _Specular * spec * _LightColor0.rgb;

                // Atenuación (la spot y point se van apagando con la distancia)
                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                return fixed4((diffuse + specular) * atten, 1.0);
            }
            ENDCG
        }
    }
}