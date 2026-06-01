using UnityEngine;

public class CameraSwitcher : MonoBehaviour
{
    [Header("configuracion de objetivos")]
    [Tooltip("arrastra aqui los gameobjects que la camara debe enfocar")]
    public Transform[] targets;
    
    [Header("configuracion de orbita")]
    public float orbitDistance = 4f;
    // usamos un vector3 para poder forzar el centro hacia abajo con valores negativos en y
    public Vector3 focusOffset = new Vector3(0f, -1f, 0f); 
    public float rotationSpeed = 5f;
    
    [Header("limites de rotacion vertical")]
    public float minPitch = -20f;
    public float maxPitch = 80f;

    private int currentIndex = 0;
    
    private float yaw = 0f;
    private float pitch = 20f;

    void Update()
    {
        // evitar errores si el array esta vacio
        if (targets == null || targets.Length == 0) return;

        HandleInput();
    }

    void LateUpdate()
    {
        if (targets == null || targets.Length == 0) return;

        MoveAndFocusCamera();
    }

    private void HandleInput()
    {
        // avanzar al siguiente objetivo
        if (Input.GetKeyDown(KeyCode.RightArrow))
        {
            currentIndex = (currentIndex + 1) % targets.Length;
        }
        // retroceder al objetivo anterior
        else if (Input.GetKeyDown(KeyCode.LeftArrow))
        {
            currentIndex--;
            if (currentIndex < 0)
            {
                // ir al ultimo si bajamos de cero
                currentIndex = targets.Length - 1; 
            }
        }

        // capturar movimiento del raton en ambos ejes de forma instantanea
        yaw += Input.GetAxis("Mouse X") * rotationSpeed;
        pitch -= Input.GetAxis("Mouse Y") * rotationSpeed;
        
        // restringir el movimiento vertical
        pitch = Mathf.Clamp(pitch, minPitch, maxPitch);
    }

    private void MoveAndFocusCamera()
    {
        Transform currentTarget = targets[currentIndex];

        // punto central hacia donde mirara la camara aplicando el nuevo offset
        Vector3 targetCenter = currentTarget.position + focusOffset;

        // calcular la rotacion basada en la entrada del raton
        Quaternion orbitRotation = Quaternion.Euler(pitch, yaw, 0f);

        // asignar la posicion de forma directa e instantanea
        transform.position = targetCenter - (orbitRotation * Vector3.forward * orbitDistance);

        // forzar a la camara a mirar exactamente al centro ajustado
        transform.LookAt(targetCenter);
    }
}