Shader "Custom/BlinnPhongShader_Procedural"
{
    Properties
    {
        // --- colores del marmol ---
        _ColorA     ("color base (fondo)",    Color)  = (0.9, 0.9, 0.88, 1)   // blanco cremoso
        _ColorB     ("color venas",           Color)  = (0.25, 0.22, 0.20, 1) // gris oscuro/negro

        // --- control del patron de marmol ---
        _MarbleScale ("escala del marmol",    Range(0.1, 10.0)) = 3.0  // que tan "grande" es el patron
        _VeinWidth   ("grosor de las venas",  Range(0.0, 1.0))  = 0.45 // 0 = muy pocas venas, 1 = casi todo es vena

        // --- iluminacion blinn-phong ---
        _Alpha      ("transparencia",         Range(0,1))   = 1.0
        _Ambient    ("intensidad ambiente",   Range(0,1))   = 0.2
        _Diffuse    ("intensidad difusa",     Range(0,1))   = 0.8
        _Specular   ("intensidad especular",  Range(0,1))   = 0.5
        _Shininess  ("brillo especular",      Range(1,256)) = 64
    }

    SubShader
    {
        Tags { "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        // ------------------------------------------------------------------
        // pass principal: luz direccional + ambiente
        // ------------------------------------------------------------------
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4  _ColorA;
            fixed4  _ColorB;
            float   _MarbleScale;
            float   _VeinWidth;
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
                float4 pos      : SV_POSITION;
                float3 normal   : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            // -----------------------------------------------------------------
            // noise y marble: la idea es sumar varias ondas de seno con
            // distintas frecuencias para romper la repeticion y simular venas.
            // es la version mas simple posible, sin tablas de permutacion.
            // -----------------------------------------------------------------

            // pseudo-ruido barato basado en seno: toma un punto 3d y devuelve
            // un valor entre 0 y 1 que parece aleatorio pero es deterministico
            float cheapNoise(float3 p)
            {
                return frac(sin(dot(p, float3(127.1, 311.7, 74.9))) * 43758.5453);
            }

            // suma de varios cheapNoise a distintas escalas (fractal basico)
            // cuantas mas "octavas", mas detalle tienen las venas
            float fbm(float3 p)
            {
                float val  = 0.0;
                float amp  = 0.5;   // amplitud inicial
                float freq = 1.0;   // frecuencia inicial

                // 3 octavas es suficiente para marmol simple
                for (int k = 0; k < 3; k++)
                {
                    // interpolamos con seno para suavizar el ruido puntual
                    float3 ip = floor(p * freq);
                    float3 fp = frac(p * freq);
                    fp = fp * fp * (3.0 - 2.0 * fp); // smoothstep manual

                    // mezclamos 8 esquinas del cubo (trilinear)
                    float n000 = cheapNoise(ip);
                    float n100 = cheapNoise(ip + float3(1,0,0));
                    float n010 = cheapNoise(ip + float3(0,1,0));
                    float n110 = cheapNoise(ip + float3(1,1,0));
                    float n001 = cheapNoise(ip + float3(0,0,1));
                    float n101 = cheapNoise(ip + float3(1,0,1));
                    float n011 = cheapNoise(ip + float3(0,1,1));
                    float n111 = cheapNoise(ip + float3(1,1,1));

                    float nx00 = lerp(n000, n100, fp.x);
                    float nx10 = lerp(n010, n110, fp.x);
                    float nx01 = lerp(n001, n101, fp.x);
                    float nx11 = lerp(n011, n111, fp.x);
                    float nxy0 = lerp(nx00, nx10, fp.y);
                    float nxy1 = lerp(nx01, nx11, fp.y);

                    val  += amp * lerp(nxy0, nxy1, fp.z);
                    amp  *= 0.5;
                    freq *= 2.0;
                }
                return val;
            }

            // funcion de marmol: usa seno + ruido para crear las venas
            // el seno da la forma de bandas, el ruido las tuerce y distorsiona
            float marble(float3 p)
            {
                float n = fbm(p);                        // ruido fractal
                float wave = sin(p.x * _MarbleScale + n * 6.0); // onda de venas
                wave = wave * 0.5 + 0.5;                // remap a [0,1]
                return wave;
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
                // --- color procedural del marmol ---
                // usamos la posicion en object space para que el patron no se mueva con el objeto
                float3 objPos = mul(unity_WorldToObject, float4(i.worldPos, 1.0)).xyz;
                float  m      = marble(objPos);

                // smoothstep centra las venas: valores cercanos a 0.5 seran _ColorB
                // _VeinWidth controla cuanto espacio ocupa la vena
                float  vein   = 1.0 - smoothstep(_VeinWidth - 0.15, _VeinWidth + 0.15, abs(m - 0.5) * 2.0);
                fixed3 baseColor = lerp(_ColorA.rgb, _ColorB.rgb, vein);

                // --- iluminacion blinn-phong ---
                float3 N = normalize(i.normal);
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                float3 ambient  = _Ambient * baseColor;
                float  diff     = max(dot(N, L), 0.0);
                float3 diffuse  = _Diffuse * diff * baseColor * _LightColor0.rgb;
                float  spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float3 specular = _Specular * spec * _LightColor0.rgb;

                float3 result = ambient + diffuse + specular;
                float  alpha  = _Alpha;
                return fixed4(result, alpha);
            }
            ENDCG
        }

        // ------------------------------------------------------------------
        // pass adicional: point lights y spot lights
        // ------------------------------------------------------------------
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

            fixed4  _ColorA;
            fixed4  _ColorB;
            float   _MarbleScale;
            float   _VeinWidth;
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

            // mismas funciones de ruido y marmol que en el pass anterior
            float cheapNoise(float3 p)
            {
                return frac(sin(dot(p, float3(127.1, 311.7, 74.9))) * 43758.5453);
            }

            float fbm(float3 p)
            {
                float val  = 0.0;
                float amp  = 0.5;
                float freq = 1.0;
                for (int k = 0; k < 3; k++)
                {
                    float3 ip = floor(p * freq);
                    float3 fp = frac(p * freq);
                    fp = fp * fp * (3.0 - 2.0 * fp);
                    float n000 = cheapNoise(ip);
                    float n100 = cheapNoise(ip + float3(1,0,0));
                    float n010 = cheapNoise(ip + float3(0,1,0));
                    float n110 = cheapNoise(ip + float3(1,1,0));
                    float n001 = cheapNoise(ip + float3(0,0,1));
                    float n101 = cheapNoise(ip + float3(1,0,1));
                    float n011 = cheapNoise(ip + float3(0,1,1));
                    float n111 = cheapNoise(ip + float3(1,1,1));
                    float nx00 = lerp(n000, n100, fp.x);
                    float nx10 = lerp(n010, n110, fp.x);
                    float nx01 = lerp(n001, n101, fp.x);
                    float nx11 = lerp(n011, n111, fp.x);
                    float nxy0 = lerp(nx00, nx10, fp.y);
                    float nxy1 = lerp(nx01, nx11, fp.y);
                    val  += amp * lerp(nxy0, nxy1, fp.z);
                    amp  *= 0.5;
                    freq *= 2.0;
                }
                return val;
            }

            float marble(float3 p)
            {
                float n    = fbm(p);
                float wave = sin(p.x * _MarbleScale + n * 6.0);
                return wave * 0.5 + 0.5;
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
                // color del marmol (igual que en el pass base)
                float3 objPos = mul(unity_WorldToObject, float4(i.worldPos, 1.0)).xyz;
                float  m      = marble(objPos);
                float  vein   = 1.0 - smoothstep(_VeinWidth - 0.15, _VeinWidth + 0.15, abs(m - 0.5) * 2.0);
                fixed3 baseColor = lerp(_ColorA.rgb, _ColorB.rgb, vein);

                float3 N = normalize(i.normal);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);

                #ifdef USING_DIRECTIONAL_LIGHT
                    float3 L = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    float3 L = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
                #endif

                float3 H = normalize(L + V);

                float  diff     = max(dot(N, L), 0.0);
                float3 diffuse  = _Diffuse * diff * baseColor * _LightColor0.rgb;
                float  spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float3 specular = _Specular * spec * _LightColor0.rgb;

                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                return fixed4((diffuse + specular) * atten, 1.0);
            }
            ENDCG
        }
    }
}
