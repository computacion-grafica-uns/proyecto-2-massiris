using UnityEngine;

[RequireComponent(typeof(CharacterController))]
public class FirstPersonController : MonoBehaviour
{
    [Header("Movimiento")]
    public float moveSpeed = 5f;
    public float rotationSpeed = 80f;

    [Header("Cámara (mirar arriba/abajo)")]
    public Transform cameraTransform;
    public float mouseSensitivity = 2f;
    public float maxLookAngle = 80f;

    private CharacterController _cc;
    private float _cameraPitch = 0f;   // rotación vertical acumulada

    void Start()
    {
        _cc = GetComponent<CharacterController>();
        Cursor.lockState = CursorLockMode.Locked;  // oculta y fija el cursor
    }

    void Update()
    {
        HandleMovement();
        HandleRotation();
    }

    void HandleMovement()
    {
        // WASD o flechas
        float h = Input.GetAxis("Horizontal");   // A/D → strafe (opcional)
        float v = Input.GetAxis("Vertical");     // W/S → adelante/atrás

        Vector3 move = transform.forward * v + transform.right * h;
        _cc.SimpleMove(move * moveSpeed);        // SimpleMove ya aplica gravedad
    }

    void HandleRotation()
    {
        // Rotación horizontal del cuerpo (izquierda/derecha)
        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        transform.Rotate(Vector3.up, mouseX);

        // Rotación vertical de la cámara (arriba/abajo)
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;
        _cameraPitch -= mouseY;
        _cameraPitch = Mathf.Clamp(_cameraPitch, -maxLookAngle, maxLookAngle);

        if (cameraTransform != null)
            cameraTransform.localEulerAngles = new Vector3(_cameraPitch, 0f, 0f);
    }

    // Presionar Escape para liberar el cursor
    void LateUpdate()
    {
        if (Input.GetKeyDown(KeyCode.Escape))
            Cursor.lockState = CursorLockMode.None;
    }
}