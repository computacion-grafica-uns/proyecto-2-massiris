using UnityEngine;

public class CameraSwitcher : MonoBehaviour
{
    [Header("Configuracion de Objetivos")]
    [Tooltip("Arrastra aqui los GameObjects que la camara debe enfocar.")]
    public Transform[] targets;
    
    [Header("Configuracion de Camara")]
    [Tooltip("La distancia y altura de la camara respecto al objeto (X, Y, Z).")]
    public Vector3 cameraOffset = new Vector3(0f, 2f, -3f);
    
    [Tooltip("Tiempo que tarda la camara en llegar al objetivo (menor es mas rapido).")]
    public float smoothTime = 0.3f;

    private int currentIndex = 0;
    private Vector3 velocity = Vector3.zero;

    void Update()
    {
        // Evitar errores si el array esta vacio
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
        // Flecha Derecha: Avanzar en el array usando el operador modulo para crear un ciclo infinito
        if (Input.GetKeyDown(KeyCode.RightArrow))
        {
            currentIndex = (currentIndex + 1) % targets.Length;
        }
        // Flecha Izquierda: Retroceder en el array
        else if (Input.GetKeyDown(KeyCode.LeftArrow))
        {
            currentIndex--;
            if (currentIndex < 0)
            {
                currentIndex = targets.Length - 1; // Volver al final si bajamos de 0
            }
        }
    }

    private void MoveAndFocusCamera()
    {
        Transform currentTarget = targets[currentIndex];

        // 1. Calcular la posicion deseada aplicando el offset
        Vector3 targetPosition = currentTarget.position + cameraOffset;

        // 2. Mover la camara suavemente hacia la posicion deseada
        transform.position = Vector3.SmoothDamp(transform.position, targetPosition, ref velocity, smoothTime);

        // 3. Rotar la camara suavemente para que siempre mire al objeto
        Quaternion targetRotation = Quaternion.LookRotation(currentTarget.position - transform.position);
        
        // Usamos Slerp para una interpolacion esferica de la rotacion
        transform.rotation = Quaternion.Slerp(transform.rotation, targetRotation, Time.deltaTime * 5f);
    }
}