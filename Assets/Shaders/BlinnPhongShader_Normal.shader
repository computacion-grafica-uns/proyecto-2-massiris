Shader "Custom/BlinnPhongShader_Normal"
{
    Properties
    {
        _Color      ("Color base",          Color)      = (0.6, 0.3, 0.15, 1)
        _Ambient    ("Intensidad ambiente",  Range(0,1)) = 0.2
        _Diffuse    ("Intensidad difusa",    Range(0,1)) = 0.8
        _Specular   ("Intensidad especular", Range(0,1)) = 0.3
        _Shininess  ("Brillo especular",     Range(1,256)) = 16

        // nueva textura: el normal map del objeto
        _NormalMap  ("Normal Map",           2D)         = "bump" {}

        // que tan fuerte se aplica el normal map (0 = sin efecto, 1 = efecto completo)
        _NormalStrength ("Fuerza del normal map", Range(0,2)) = 1.0
    }

    SubShader
    {
        Tags { "Queue"="Geometry" }
        ZWrite On

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4  _Color;
            float   _Ambient;
            float   _Diffuse;
            float   _Specular;
            float   _Shininess;
            sampler2D _NormalMap;
            float4    _NormalMap_ST;   // unity necesita esta variable para tiling y offset
            float     _NormalStrength;

            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                // la tangente viene del mesh, unity la genera automaticamente
                // el w indica la "mano" <---????????   (handedness) para calcular la bitangente
                float4 tangent : TANGENT;
                float2 uv      : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float2 uv       : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                // en vez de pasar la normal sola ahora pasamos los 3 vectores de la TBN
                float3 wNormal  : TEXCOORD2;   // normal en world space
                float3 wTangent : TEXCOORD3;   // tangente en world space
                float3 wBitan   : TEXCOORD4;   // bitangente en world space
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                // aplicamos tiling y offset del normal map a las UVs
                o.uv = TRANSFORM_TEX(v.uv, _NormalMap);

                // pasamos los 3 vectores de la TBN a world space
                o.wNormal  = UnityObjectToWorldNormal(v.normal);
                o.wTangent = UnityObjectToWorldDir(v.tangent.xyz);

                // la bitangente se calcula con el producto cruzado
                // v.tangent.w guarda el signo necesario para la mano del espacio tangente
                o.wBitan = cross(o.wNormal, o.wTangent) * v.tangent.w;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // leer la normal del mapa
                // UnpackNormal convierte los colores (0..1) a vectores (-1..1)
                float3 tangentNormal = UnpackNormal(tex2D(_NormalMap, i.uv));

                // aplicamos la fuerza: xy escala el desvio, z queda fijo en 1
                // con mas fuerza las normales se inclinan mas
                tangentNormal.xy *= _NormalStrength;

                // renormalizamos porque al escalar xy el vector puede dejar de tener longitud 1
                tangentNormal = normalize(tangentNormal);

                // construir la matriz TBN y transformar la normal
                // la TBN convierte de tangent space a world space
                // cada fila es uno de los ejes del espacio tangente expresado en world space
                float3x3 TBN = float3x3(
                    normalize(i.wTangent),
                    normalize(i.wBitan),
                    normalize(i.wNormal)
                );

                // mul con la transpuesta de TBN transforma de tangent space a world space
                float3 N = normalize(mul(tangentNormal, TBN));

                // a partir de aca es el mismo calculo blinn-phong
                float3 L = normalize(_WorldSpaceLightPos0.xyz);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 H = normalize(L + V);

                float3 ambient  = _Ambient * _Color.rgb;

                float  diff     = max(dot(N, L), 0.0);
                float3 diffuse  = _Diffuse * diff * _Color.rgb * _LightColor0.rgb;

                float  spec     = pow(max(dot(N, H), 0.0), _Shininess);
                float3 specular = _Specular * spec * _LightColor0.rgb;

                float3 result = ambient + diffuse + specular;
                return fixed4(result, 1.0);
            }
            ENDCG
        }

        // segundo pass: luces adicionales (point y spot)
        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            ZWrite Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdadd
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            fixed4    _Color;
            float     _Diffuse;
            float     _Specular;
            float     _Shininess;
            sampler2D _NormalMap;
            float4    _NormalMap_ST;
            float     _NormalStrength;

            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                float4 tangent : TANGENT;
                float2 uv      : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float2 uv       : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 wNormal  : TEXCOORD2;
                float3 wTangent : TEXCOORD3;
                float3 wBitan   : TEXCOORD4;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos      = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv       = TRANSFORM_TEX(v.uv, _NormalMap);

                o.wNormal  = UnityObjectToWorldNormal(v.normal);
                o.wTangent = UnityObjectToWorldDir(v.tangent.xyz);
                o.wBitan   = cross(o.wNormal, o.wTangent) * v.tangent.w;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 tangentNormal = UnpackNormal(tex2D(_NormalMap, i.uv));
                tangentNormal.xy    *= _NormalStrength;
                tangentNormal        = normalize(tangentNormal);

                float3x3 TBN = float3x3(
                    normalize(i.wTangent),
                    normalize(i.wBitan),
                    normalize(i.wNormal)
                );

                float3 N = normalize(mul(tangentNormal, TBN));
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);

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

                UNITY_LIGHT_ATTENUATION(atten, 0, i.worldPos);

                return fixed4((diffuse + specular) * atten, 1.0);
            }
            ENDCG
        }
    }
}
